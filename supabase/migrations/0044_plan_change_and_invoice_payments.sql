-- ============================================================================
-- Migración 0044 — El cambio de plan llega a todos lados, y pagar una factura
-- no provoca un doble cobro con tarjeta.
--
-- A) update_business_membership (misma firma que 0007)
--    Escribía plan_type SOLO en la membresía más reciente del negocio, de
--    cualquier usuario. La ancla de facturación —la fila que lee el POS y que
--    cobra el cron— podía quedar con el plan viejo: se cambiaba el plan en la
--    consola y al cliente se le seguía mostrando y cobrando el anterior.
--    Ahora:
--      * plan_type va a TODAS las membresías del negocio. El plan es del
--        negocio, no del usuario. El trigger fn_sync_membership_plan_id
--        re-deriva plan_id en cada fila, incluida la ancla.
--      * estado y fecha de corte siguen yendo a la misma fila que antes: cada
--        usuario tiene su membresía y esos campos pueden gatear su acceso, así
--        que no se escriben en masa.
--      * el plan se valida contra plan_catalog (antes: lista fija de 4).
--      * queda en noc_audit_log.
--    El precio nuevo se cobra en el PRÓXIMO cobro (decisión 2026-09-15): sin
--    cobro ni crédito inmediato. Un precio especial acordado para el plan
--    anterior deja de aplicar solo (está amarrado al plan, 20260915_0006).
--
-- B) admin_mark_invoices_paid(ids[], método, referencia, fecha, dry_run)
--    Marca varias facturas como pagadas de una vez. Si una factura cubre la
--    fecha en que la tarjeta iba a cobrar (next_billing_date dentro del
--    período de la factura), el próximo cobro pasa al día siguiente al fin de
--    ese período, igual que si ese mes se hubiera cobrado con tarjeta: estado
--    activo, intentos en 0. Sin esto, el cliente que paga por transferencia
--    recibe además el cobro del cron (decisión 2026-09-15).
--    dry_run corre EXACTAMENTE la misma lógica y la revierte: la vista previa
--    de la UI no puede diferir de lo que después pasa.
--
-- C) mark_invoice_paid (misma firma que 0004) delega en B: el pago individual
--    tampoco provoca doble cobro.
--
-- Solo operadores. Idempotente.
-- ============================================================================

begin;

-- Sin el trigger de sincronización, cambiar plan_type no llega a plan_id y el
-- cron seguiría cobrando el plan viejo. Mejor fallar acá que en silencio.
do $$
begin
  if not exists (
    select 1 from pg_trigger
     where tgname = 'trg_sync_membership_plan_id'
       and tgrelid = 'public.memberships'::regclass
  ) then
    raise exception
      'Falta el trigger trg_sync_membership_plan_id (mangospos 20260617_0002). Aplicarlo antes que 0044.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- A) update_business_membership
-- ---------------------------------------------------------------------------
create or replace function public.update_business_membership(
  p_business_id uuid,
  p_plan_type   text,
  p_end_date    timestamptz,
  p_status      text
) returns public.memberships
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_membership public.memberships;
  v_anchor     public.memberships;
  v_owner_id   uuid;
  v_before     jsonb;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.plan_catalog
     where code = p_plan_type
       and archived_at is null
  ) then
    raise exception 'Plan inválido o archivado: %', p_plan_type using errcode = '22023';
  end if;

  if p_status not in ('active', 'canceled', 'expired') then
    raise exception 'Estado inválido: %', p_status using errcode = '22023';
  end if;

  select * into v_anchor
    from public.memberships
   where business_id = p_business_id
     and is_billing_anchor = true
   limit 1;

  -- Membresía más reciente del negocio (cualquier estado): la que editaba 0007.
  select * into v_membership
    from public.memberships
   where business_id = p_business_id
   order by created_at desc
   limit 1;

  v_before := jsonb_build_object(
    'plan_type',        v_membership.plan_type,
    'status',           v_membership.status,
    'end_date',         v_membership.end_date,
    'anchor_plan_type', v_anchor.plan_type
  );

  if v_membership.id is null then
    select owner_id into v_owner_id
      from public.businesses
     where id = p_business_id;

    if v_owner_id is null then
      raise exception 'Negocio % no existe', p_business_id;
    end if;

    insert into public.memberships (
      user_id, business_id, plan_type, status, start_date, end_date, role
    )
    values (
      v_owner_id, p_business_id, p_plan_type, p_status, now(), p_end_date,
      'owner'::public.member_role
    )
    returning * into v_membership;
  else
    update public.memberships
       set status   = p_status,
           end_date = p_end_date
     where id = v_membership.id;

    -- El plan es del NEGOCIO: todas sus membresías, incluida la ancla. Sin
    -- filtro "si cambió": el trigger re-deriva plan_id y corrige de paso un
    -- plan_id desfasado.
    update public.memberships
       set plan_type = p_plan_type
     where business_id = p_business_id;

    select * into v_membership from public.memberships where id = v_membership.id;
  end if;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'membership.plan_update',
    'memberships',
    v_membership.id,
    p_business_id,
    jsonb_build_object(
      'before', v_before,
      'after',  jsonb_build_object(
        'plan_type', p_plan_type,
        'status',    p_status,
        'end_date',  p_end_date
      )
    )
  );

  return v_membership;
end;
$$;

comment on function public.update_business_membership(uuid, text, timestamptz, text) is
  'Cambia el plan del negocio (todas sus membresías, incluida la ancla de cobro) y el estado/fecha de corte de su membresía más reciente. Solo operadores; audita.';

grant execute on function public.update_business_membership(uuid, text, timestamptz, text) to authenticated;

-- ---------------------------------------------------------------------------
-- B) Pago de facturas
-- ---------------------------------------------------------------------------

-- Lógica compartida. NO valida operador: la llaman las RPC que sí lo hacen.
create or replace function public.fn_apply_invoice_payments(
  p_invoice_ids uuid[],
  p_method      text,
  p_reference   text,
  p_paid_at     timestamptz
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_inv      record;
  v_anchor   public.memberships;
  v_new_next date;
  v_paid     jsonb := '[]'::jsonb;
  v_skipped  jsonb := '[]'::jsonb;
  v_moved    jsonb := '[]'::jsonb;
begin
  select coalesce(
           jsonb_agg(jsonb_build_object('invoice_id', x.id, 'reason', 'not_found')),
           '[]'::jsonb
         )
    into v_skipped
    from unnest(p_invoice_ids) as x(id)
   where not exists (
     select 1 from public.membership_invoices mi where mi.id = x.id
   );

  -- Por negocio y período: si se pagan octubre y noviembre juntos, el próximo
  -- cobro avanza dos veces y en el orden correcto.
  for v_inv in
    select mi.*, b.business_name
      from public.membership_invoices mi
      join public.businesses b on b.id = mi.business_id
     where mi.id = any(p_invoice_ids)
     order by mi.business_id, mi.period_start
       for update of mi
  loop
    if v_inv.status not in ('pending', 'expired') then
      v_skipped := v_skipped || jsonb_build_object(
        'invoice_id',     v_inv.id,
        'invoice_number', v_inv.invoice_number,
        'business_name',  v_inv.business_name,
        'reason',         v_inv.status
      );
      continue;
    end if;

    update public.membership_invoices
       set status            = 'paid',
           paid_at           = p_paid_at,
           paid_by           = auth.uid(),
           payment_method    = p_method,
           payment_reference = coalesce(p_reference, payment_reference)
     where id = v_inv.id;

    v_paid := v_paid || jsonb_build_object(
      'invoice_id',     v_inv.id,
      'invoice_number', v_inv.invoice_number,
      'business_id',    v_inv.business_id,
      'business_name',  v_inv.business_name,
      'total',          v_inv.total
    );

    insert into public.noc_audit_log (
      user_id, action, target_resource, target_id, business_id, payload
    )
    values (
      auth.uid(), 'invoice.paid', 'membership_invoices', v_inv.id, v_inv.business_id,
      jsonb_build_object(
        'invoice_number', v_inv.invoice_number,
        'total',          v_inv.total,
        'method',         p_method,
        'reference',      p_reference,
        'paid_at',        p_paid_at
      )
    );

    -- ¿Esta factura cubre la fecha en que la tarjeta iba a cobrar?
    select * into v_anchor
      from public.memberships
     where business_id = v_inv.business_id
       and is_billing_anchor = true
     limit 1
       for update;

    if v_anchor.id is not null
       and v_anchor.billing_status in ('active', 'past_due')
       and v_anchor.next_billing_date is not null
       and v_anchor.next_billing_date between v_inv.period_start and v_inv.period_end
    then
      v_new_next := v_inv.period_end + 1;

      update public.memberships
         set next_billing_date      = v_new_next,
             current_period_start   = v_inv.period_start,
             current_period_end     = v_new_next,
             current_attempt_number = 0,
             billing_status         = 'active'
       where id = v_anchor.id;

      v_moved := v_moved || jsonb_build_object(
        'business_id',    v_inv.business_id,
        'business_name',  v_inv.business_name,
        'invoice_number', v_inv.invoice_number,
        'from',           v_anchor.next_billing_date,
        'to',             v_new_next,
        'was_past_due',   v_anchor.billing_status = 'past_due'
      );

      insert into public.noc_audit_log (
        user_id, action, target_resource, target_id, business_id, payload
      )
      values (
        auth.uid(), 'subscription.next_charge_moved', 'memberships', v_anchor.id, v_inv.business_id,
        jsonb_build_object(
          'reason',     format('Factura %s pagada (%s)', v_inv.invoice_number, p_method),
          'invoice_id', v_inv.id,
          'before', jsonb_build_object(
            'next_billing_date',      v_anchor.next_billing_date,
            'billing_status',         v_anchor.billing_status,
            'current_attempt_number', v_anchor.current_attempt_number
          ),
          'after', jsonb_build_object(
            'next_billing_date',      v_new_next,
            'billing_status',         'active',
            'current_attempt_number', 0
          )
        )
      );
    end if;
  end loop;

  return jsonb_build_object('paid', v_paid, 'skipped', v_skipped, 'moved', v_moved);
end;
$$;

revoke all on function public.fn_apply_invoice_payments(uuid[], text, text, timestamptz)
  from public, anon, authenticated;

create or replace function public.admin_mark_invoices_paid(
  p_invoice_ids uuid[],
  p_method      text,
  p_reference   text        default null,
  p_paid_at     timestamptz default null,
  p_dry_run     boolean     default false
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_method    text        := nullif(trim(coalesce(p_method, '')), '');
  v_reference text        := nullif(trim(coalesce(p_reference, '')), '');
  v_paid_at   timestamptz := coalesce(p_paid_at, now());
  v_result    jsonb;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_invoice_ids is null or cardinality(p_invoice_ids) = 0 then
    raise exception 'No hay facturas seleccionadas' using errcode = '22023';
  end if;

  if cardinality(p_invoice_ids) > 500 then
    raise exception 'Máximo 500 facturas por operación' using errcode = '22023';
  end if;

  if v_method is null then
    raise exception 'El método de pago es obligatorio' using errcode = '22023';
  end if;

  if v_paid_at > now() + interval '1 day' then
    raise exception 'La fecha de pago no puede estar en el futuro' using errcode = '22023';
  end if;

  if not coalesce(p_dry_run, false) then
    return public.fn_apply_invoice_payments(p_invoice_ids, v_method, v_reference, v_paid_at)
           || jsonb_build_object('dry_run', false);
  end if;

  -- Vista previa: la misma función dentro de un bloque que se revierte. Las
  -- variables locales sobreviven al rollback del bloque; las filas no.
  begin
    v_result := public.fn_apply_invoice_payments(p_invoice_ids, v_method, v_reference, v_paid_at);
    raise exception using errcode = 'MGDRY', message = 'dry_run';
  exception when sqlstate 'MGDRY' then
    null;
  end;

  return v_result || jsonb_build_object('dry_run', true);
end;
$$;

comment on function public.admin_mark_invoices_paid(uuid[], text, text, timestamptz, boolean) is
  'Marca facturas como pagadas. Si una cubre la fecha del próximo cobro con tarjeta, lo corre al fin de ese período para no cobrar dos veces. dry_run devuelve el impacto sin escribir. Solo operadores; audita.';

grant execute on function public.admin_mark_invoices_paid(uuid[], text, text, timestamptz, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- C) mark_invoice_paid — misma firma y retorno que 0004.
-- ---------------------------------------------------------------------------
create or replace function public.mark_invoice_paid(
  p_invoice_id uuid,
  p_method     text,
  p_reference  text default null
)
returns public.membership_invoices
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_invoice public.membership_invoices;
  v_result  jsonb;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  v_result := public.fn_apply_invoice_payments(
    array[p_invoice_id],
    coalesce(nullif(trim(coalesce(p_method, '')), ''), 'cash'),
    nullif(trim(coalesce(p_reference, '')), ''),
    now()
  );

  if jsonb_array_length(v_result->'paid') = 0 then
    raise exception 'Factura % no existe o no se puede marcar como pagada', p_invoice_id;
  end if;

  select * into v_invoice from public.membership_invoices where id = p_invoice_id;
  return v_invoice;
end;
$$;

grant execute on function public.mark_invoice_paid(uuid, text, text) to authenticated;

commit;

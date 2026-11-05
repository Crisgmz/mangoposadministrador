-- ============================================================================
-- Migración 0053 — Editar facturas, elegir el precio al cobrar y usar la
-- tarjeta de otro negocio del mismo dueño.
--
-- A) admin_update_invoice(id, total?, vence?, notas?)
--    Cambia una factura PENDIENTE o VENCIDA: el total a cobrar, la fecha de
--    vencimiento y las notas. Las pagadas y anuladas no se tocan: se anulan y
--    se hace otra. El total respeta el ITBIS de la factura: si se cobraba
--    aparte (18%), el total nuevo lo incluye y se separa; si estaba incluido,
--    sigue incluido. La parte de e-CF extra (0051) se conserva; si el total
--    nuevo queda por debajo, el descuento cae primero sobre el plan y la
--    parte de e-CF se recorta al monto. Cada cambio de monto deja una nota en
--    la factura ("Monto ajustado de RD$X a RD$Y.") y todo queda en
--    noc_audit_log. Mover el vencimiento al futuro devuelve una vencida a
--    pendiente.
--
-- B) admin_mark_invoices_paid(..., p_totals)
--    Misma función de 0044 con un parámetro más, opcional y al final:
--    {"<invoice_id>": total} para cobrar otro precio. El cambio de monto y el
--    pago van en la MISMA transacción (si el pago falla, el monto no cambia) y
--    la vista previa (dry_run) lo incluye y lo revierte igual que el resto. El
--    pago queda registrado con el monto cobrado (Pagos y "Último pago" lo leen
--    de la factura). Sin p_totals se comporta exactamente como antes.
--
-- C) admin_list_owner_cards(negocio) / admin_copy_payment_method(...)
--    Un dueño con varios negocios no tiene que volver a meter la tarjeta (ni
--    pasar otra vez por la verificación de RD$1) en cada uno: la tarjeta
--    verificada de un negocio se copia a otro negocio del MISMO dueño
--    (businesses.owner_id). Se copia el token de DataVault: Azul cobra con el
--    token, sin importar el negocio. El operador confirma que el dueño
--    autorizó cobrar esa tarjeta también al otro negocio; queda en la
--    auditoría. Ningún flujo borra tokens en Azul al quitar una tarjeta, así
--    que compartir el token no rompe al otro negocio.
--
-- Solo operadores. DEPENDE de 0044 y 0051. Idempotente.
-- ============================================================================

begin;

do $$
begin
  if to_regprocedure('public.fn_apply_invoice_payments(uuid[],text,text,timestamptz)') is null then
    raise exception 'Falta 0044 (fn_apply_invoice_payments). Aplicarla antes que 0053.';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'membership_invoices'
       and column_name = 'ecf_overage_amount'
  ) then
    raise exception 'Falta 0051 (membership_invoices.ecf_overage_amount). Aplicarla antes que 0053.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- A) Monto de una factura
-- ---------------------------------------------------------------------------

-- Interna: cambia el total de una factura pendiente o vencida. La usan
-- admin_update_invoice y admin_mark_invoices_paid (que validan el operador).
create or replace function public.fn_set_invoice_total(
  p_invoice_id uuid,
  p_total      numeric
) returns public.membership_invoices
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_inv          public.membership_invoices;
  v_total        numeric := round(p_total, 2);
  v_tax_included boolean;
  v_taxed        boolean;
  v_amount       numeric;
  v_itbis        numeric;
  v_before       jsonb;
begin
  select * into v_inv
    from public.membership_invoices
   where id = p_invoice_id
   for update;
  if v_inv.id is null then
    raise exception 'Factura % no encontrada', p_invoice_id using errcode = 'P0002';
  end if;
  if v_inv.status not in ('pending', 'expired') then
    raise exception 'La factura % está %: solo se cambia el monto de una pendiente o vencida.',
      v_inv.invoice_number, v_inv.status using errcode = '22023';
  end if;
  if v_total is null or v_total < 0 then
    raise exception 'El monto de % no puede ser negativo.', v_inv.invoice_number
      using errcode = '22023';
  end if;
  if v_total = v_inv.total then
    return v_inv;
  end if;

  -- Mismo ITBIS que la factura: aparte si se cobró aparte. Una factura en 0
  -- (crédito aplicado) no lo dice: manda el plan, como al generarla.
  select coalesce(pc.tax_included, true) into v_tax_included
    from public.plan_catalog pc
   where pc.code = v_inv.plan_type;
  v_taxed := v_inv.itbis > 0
          or (v_inv.amount = 0 and not coalesce(v_tax_included, true));

  if v_taxed then
    v_amount := round(v_total / 1.18, 2);
    v_itbis  := v_total - v_amount;
  else
    v_amount := v_total;
    v_itbis  := 0;
  end if;

  v_before := jsonb_build_object(
    'amount', v_inv.amount, 'itbis', v_inv.itbis, 'total', v_inv.total,
    'ecf_overage_amount', v_inv.ecf_overage_amount);

  update public.membership_invoices
     set amount             = v_amount,
         itbis              = v_itbis,
         ecf_overage_amount = least(coalesce(ecf_overage_amount, 0), v_amount),
         notes              = concat_ws(' ', nullif(notes, ''), format(
                                'Monto ajustado de RD$%s a RD$%s.',
                                to_char(v_inv.total, 'FM999,999,990.00'),
                                to_char(v_total, 'FM999,999,990.00')))
   where id = p_invoice_id
  returning * into v_inv;

  insert into public.noc_audit_log (user_id, action, target_resource, target_id, business_id, payload)
  values (
    auth.uid(), 'invoice.total_changed', 'membership_invoices', v_inv.id, v_inv.business_id,
    jsonb_build_object(
      'invoice_number', v_inv.invoice_number,
      'before', v_before,
      'after', jsonb_build_object(
        'amount', v_inv.amount, 'itbis', v_inv.itbis, 'total', v_inv.total,
        'ecf_overage_amount', v_inv.ecf_overage_amount))
  );

  return v_inv;
end;
$$;

revoke all on function public.fn_set_invoice_total(uuid, numeric) from public, anon, authenticated;

create or replace function public.admin_update_invoice(
  p_invoice_id uuid,
  p_total      numeric default null,
  p_due_date   date    default null,
  -- null = no se tocan; '' = se borran.
  p_notes      text    default null
) returns public.membership_invoices
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_inv    public.membership_invoices;
  v_before public.membership_invoices;
  v_due    timestamptz;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_total is null and p_due_date is null and p_notes is null then
    raise exception 'No hay nada que cambiar.' using errcode = '22023';
  end if;

  select * into v_inv
    from public.membership_invoices
   where id = p_invoice_id
   for update;
  if v_inv.id is null then
    raise exception 'Factura % no encontrada', p_invoice_id using errcode = 'P0002';
  end if;
  if v_inv.status not in ('pending', 'expired') then
    raise exception 'La factura % está %: solo se editan las pendientes o vencidas. Anúlala y genera otra.',
      v_inv.invoice_number, v_inv.status using errcode = '22023';
  end if;
  v_before := v_inv;

  -- Notas antes que el monto: la nota automática del ajuste se agrega a las
  -- notas nuevas en vez de perderse.
  if p_notes is not null or p_due_date is not null then
    v_due := case when p_due_date is null then v_inv.due_date
                  else p_due_date::timestamp at time zone 'America/Santo_Domingo' end;
    update public.membership_invoices
       set notes    = case when p_notes is null then notes else nullif(btrim(p_notes), '') end,
           due_date = v_due,
           -- Con el vencimiento en el futuro deja de estar vencida.
           status   = case when status = 'expired' and v_due > now() then 'pending' else status end
     where id = p_invoice_id
    returning * into v_inv;
  end if;

  if p_total is not null then
    v_inv := public.fn_set_invoice_total(p_invoice_id, p_total);
  end if;

  if p_notes is not null or p_due_date is not null then
    insert into public.noc_audit_log (user_id, action, target_resource, target_id, business_id, payload)
    values (
      auth.uid(), 'invoice.updated', 'membership_invoices', v_inv.id, v_inv.business_id,
      jsonb_build_object(
        'invoice_number', v_inv.invoice_number,
        'before', jsonb_build_object('due_date', v_before.due_date, 'status', v_before.status, 'notes', v_before.notes),
        'after',  jsonb_build_object('due_date', v_inv.due_date, 'status', v_inv.status, 'notes', v_inv.notes))
    );
  end if;

  return v_inv;
end;
$$;

comment on function public.admin_update_invoice(uuid, numeric, date, text) is
  'Edita una factura pendiente o vencida: total (respeta su ITBIS), vencimiento y notas. Solo operadores; audita (0053).';

grant execute on function public.admin_update_invoice(uuid, numeric, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- B) Pagar con otro precio
-- ---------------------------------------------------------------------------

-- Interna: aplica {"<invoice_id>": total} a las facturas que se van a pagar.
-- Las que ya no se pueden pagar se dejan: fn_apply_invoice_payments las omite
-- y lo informa.
create or replace function public.fn_apply_invoice_totals(
  p_invoice_ids uuid[],
  p_totals      jsonb
) returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_key   text;
  v_value jsonb;
begin
  if p_totals is null then
    return;
  end if;
  for v_key, v_value in select key, value from jsonb_each(p_totals) loop
    if exists (
      select 1 from public.membership_invoices
       where id = v_key::uuid and status in ('pending', 'expired')
    ) then
      perform public.fn_set_invoice_total(v_key::uuid, (v_value #>> '{}')::numeric);
    end if;
  end loop;
end;
$$;

revoke all on function public.fn_apply_invoice_totals(uuid[], jsonb) from public, anon, authenticated;

-- Firma nueva (un parámetro más): se borra la vieja para que PostgREST no
-- tenga dos candidatas con los mismos nombres.
drop function if exists public.admin_mark_invoices_paid(uuid[], text, text, timestamptz, boolean);

create or replace function public.admin_mark_invoices_paid(
  p_invoice_ids uuid[],
  p_method      text,
  p_reference   text        default null,
  p_paid_at     timestamptz default null,
  p_dry_run     boolean     default false,
  -- {"<invoice_id>": total}: cobrar otro precio. null = el de cada factura.
  p_totals      jsonb       default null
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
  v_key       text;
  v_value     jsonb;
  v_id        uuid;
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

  -- Validar los precios ANTES de tocar nada (también en la vista previa).
  if p_totals is not null then
    if jsonb_typeof(p_totals) <> 'object' then
      raise exception 'p_totals debe ser un objeto {factura: total}' using errcode = '22023';
    end if;
    for v_key, v_value in select key, value from jsonb_each(p_totals) loop
      begin
        v_id := v_key::uuid;
      exception when invalid_text_representation then
        raise exception 'Factura inválida en los precios: %', v_key using errcode = '22023';
      end;
      if not (v_id = any(p_invoice_ids)) then
        raise exception 'El precio de % es de una factura que no se está pagando', v_key
          using errcode = '22023';
      end if;
      if jsonb_typeof(v_value) <> 'number' or (v_value #>> '{}')::numeric < 0 then
        raise exception 'Precio inválido para %: %', v_key, v_value using errcode = '22023';
      end if;
    end loop;
  end if;

  if not coalesce(p_dry_run, false) then
    perform public.fn_apply_invoice_totals(p_invoice_ids, p_totals);
    return public.fn_apply_invoice_payments(p_invoice_ids, v_method, v_reference, v_paid_at)
           || jsonb_build_object('dry_run', false);
  end if;

  -- Vista previa: la misma lógica dentro de un bloque que se revierte. Las
  -- variables locales sobreviven al rollback del bloque; las filas no.
  begin
    perform public.fn_apply_invoice_totals(p_invoice_ids, p_totals);
    v_result := public.fn_apply_invoice_payments(p_invoice_ids, v_method, v_reference, v_paid_at);
    raise exception using errcode = 'MGDRY', message = 'dry_run';
  exception when sqlstate 'MGDRY' then
    null;
  end;

  return v_result || jsonb_build_object('dry_run', true);
end;
$$;

comment on function public.admin_mark_invoices_paid(uuid[], text, text, timestamptz, boolean, jsonb) is
  'Marca facturas como pagadas, opcionalmente con otro precio por factura (p_totals). Si una cubre la fecha del próximo cobro con tarjeta, lo corre al fin de ese período para no cobrar dos veces. dry_run devuelve el impacto sin escribir. Solo operadores; audita (0044, 0053).';

grant execute on function public.admin_mark_invoices_paid(uuid[], text, text, timestamptz, boolean, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- C) Tarjeta de otro negocio del mismo dueño
-- ---------------------------------------------------------------------------

-- Tarjetas verificadas y vigentes de los OTROS negocios del dueño de
-- p_business_id. Una tarjeta ya compartida entre varios sale una sola vez.
create or replace function public.admin_list_owner_cards(p_business_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner  uuid;
  v_month  text := to_char(now() at time zone 'America/Santo_Domingo', 'YYYYMM');
  v_result jsonb;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select owner_id into v_owner from public.businesses where id = p_business_id;
  if not found then
    raise exception 'Negocio % no existe', p_business_id using errcode = 'P0002';
  end if;
  if v_owner is null then
    return '[]'::jsonb;
  end if;

  select coalesce(jsonb_agg(c order by c->>'business_name', c->>'masked'), '[]'::jsonb)
    into v_result
    from (
      select distinct on (pm.data_vault_token)
             jsonb_build_object(
               'payment_method_id', pm.id,
               'business_id',       b.id,
               'business_name',     b.business_name,
               'brand',             pm.data_vault_brand,
               'masked',            pm.card_number_masked,
               'expiration',        pm.data_vault_expiration,
               -- Ya está en este negocio: no hace falta copiarla.
               'already_here',      exists (
                 select 1 from public.azul_payment_methods t
                  where t.business_id = p_business_id
                    and t.data_vault_token = pm.data_vault_token
                    and t.status <> 'revoked'
               )
             ) as c
        from public.azul_payment_methods pm
        join public.businesses b on b.id = pm.business_id
       where b.owner_id = v_owner
         and b.id <> p_business_id
         and pm.status = 'verified'
         and pm.revoked_at is null
         and pm.data_vault_expiration >= v_month
       order by pm.data_vault_token, pm.is_default desc, pm.created_at
    ) x;

  return v_result;
end;
$$;

comment on function public.admin_list_owner_cards(uuid) is
  'Tarjetas verificadas y vigentes de los otros negocios del mismo dueño (businesses.owner_id), para copiarlas. Solo operadores (0053).';

grant execute on function public.admin_list_owner_cards(uuid) to authenticated;

create or replace function public.admin_copy_payment_method(
  p_payment_method_id  uuid,
  p_target_business_id uuid,
  p_make_default       boolean default true,
  p_client_authorized  boolean default false
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_src          public.azul_payment_methods;
  v_src_owner    uuid;
  v_target_owner uuid;
  v_existing     public.azul_payment_methods;
  v_new          public.azul_payment_methods;
  v_has_default  boolean;
  v_default      boolean;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if not coalesce(p_client_authorized, false) then
    raise exception 'Confirma que el dueño autorizó cobrar esta tarjeta también a este negocio.'
      using errcode = '22023';
  end if;

  select * into v_src
    from public.azul_payment_methods
   where id = p_payment_method_id;
  if v_src.id is null then
    raise exception 'Tarjeta % no encontrada', p_payment_method_id using errcode = 'P0002';
  end if;
  if v_src.business_id = p_target_business_id then
    raise exception 'La tarjeta ya es de este negocio.' using errcode = '22023';
  end if;
  if v_src.status <> 'verified' or v_src.revoked_at is not null then
    raise exception 'Solo se copia una tarjeta verificada (esta está %).', v_src.status
      using errcode = '22023';
  end if;
  if v_src.data_vault_expiration < to_char(now() at time zone 'America/Santo_Domingo', 'YYYYMM') then
    raise exception 'La tarjeta está vencida.' using errcode = '22023';
  end if;

  select owner_id into v_src_owner from public.businesses where id = v_src.business_id;
  select owner_id into v_target_owner from public.businesses where id = p_target_business_id;
  if not found then
    raise exception 'Negocio % no existe', p_target_business_id using errcode = 'P0002';
  end if;
  -- Nunca la tarjeta de un dueño en el negocio de otro.
  if v_src_owner is null or v_target_owner is distinct from v_src_owner then
    raise exception 'Los dos negocios no tienen el mismo dueño: no se puede usar esa tarjeta.'
      using errcode = '42501';
  end if;

  -- Una sola tarjeta default por negocio (índice parcial): serializar.
  perform 1 from public.businesses where id = p_target_business_id for update;

  select * into v_existing
    from public.azul_payment_methods
   where business_id = p_target_business_id
     and data_vault_token = v_src.data_vault_token
     and status <> 'revoked'
   limit 1;

  select exists (
    select 1 from public.azul_payment_methods
     where business_id = p_target_business_id and is_default
  ) into v_has_default;
  v_default := coalesce(p_make_default, true) or not v_has_default;

  if v_default then
    update public.azul_payment_methods
       set is_default = false
     where business_id = p_target_business_id
       and is_default
       and id is distinct from v_existing.id;
  end if;

  if v_existing.id is not null then
    -- Ya la tenía: solo se marca como principal si se pidió.
    update public.azul_payment_methods
       set is_default = v_default or is_default
     where id = v_existing.id
    returning * into v_new;
  else
    insert into public.azul_payment_methods (
      business_id, data_vault_token, data_vault_expiration, data_vault_brand,
      card_number_masked, azul_order_id_at_creation, status, is_default
    ) values (
      p_target_business_id, v_src.data_vault_token, v_src.data_vault_expiration,
      v_src.data_vault_brand, v_src.card_number_masked, v_src.azul_order_id_at_creation,
      'verified', v_default
    )
    returning * into v_new;
  end if;

  insert into public.noc_audit_log (user_id, action, target_resource, target_id, business_id, payload)
  values (
    auth.uid(), 'payment_method.copied_from_owner_business', 'azul_payment_methods',
    v_new.id, p_target_business_id,
    jsonb_build_object(
      'source_payment_method_id', v_src.id,
      'source_business_id',       v_src.business_id,
      'owner_id',                 v_src_owner,
      'card',                     concat_ws(' ', v_src.data_vault_brand, v_src.card_number_masked),
      'make_default',             v_new.is_default,
      'already_present',          v_existing.id is not null,
      'client_authorized',        true)
  );

  return jsonb_build_object(
    'payment_method_id', v_new.id,
    'brand',             v_new.data_vault_brand,
    'masked',            v_new.card_number_masked,
    'expiration',        v_new.data_vault_expiration,
    'is_default',        v_new.is_default,
    'already_present',   v_existing.id is not null
  );
end;
$$;

comment on function public.admin_copy_payment_method(uuid, uuid, boolean, boolean) is
  'Copia una tarjeta verificada (token DataVault) a otro negocio del mismo dueño. Exige la confirmación de que el dueño lo autorizó; audita. Solo operadores (0053).';

grant execute on function public.admin_copy_payment_method(uuid, uuid, boolean, boolean) to authenticated;

commit;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 0022_apply_free_credit.sql
--
-- Cierra el loop de `admin_extensions.free_credit`: cuando se genera una
-- factura de membresía, se buscan créditos activos del negocio (no
-- revertidos, no aplicados) y se aplican en orden FIFO (granted_at asc).
--
-- Política de aplicación:
--   * Si un crédito cabe completo en el remanente de la factura → se aplica
--     entero (UPDATE admin_extensions.applied_to_invoice_id).
--   * Si un crédito es mayor al remanente → NO se aplica parcial; se deja
--     activo para una factura futura. (Soporte de aplicación parcial requiere
--     columna `amount_consumed` — fuera del scope hoy.)
--   * Si la factura queda en RD$0 tras los créditos → se marca como `paid`
--     automáticamente con `payment_method='credit_applied'`. El operador no
--     necesita marcar nada.
--   * Si quedan créditos sin consumir → siguen activos para la siguiente
--     facturación.
--
-- Reemplaza `generate_membership_invoice` de 0004 manteniendo la signature.
-- ---------------------------------------------------------------------------

create or replace function public.generate_membership_invoice(p_business_id uuid)
returns public.membership_invoices
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_membership      public.memberships;
  v_period_start    date;
  v_period_end      date;
  v_due_date        timestamptz;
  v_amount_gross    numeric;
  v_amount_net      numeric;
  v_itbis_rate      numeric := 0.18;
  v_itbis           numeric;
  v_invoice         public.membership_invoices;
  v_remaining       numeric;
  v_total_applied   numeric := 0;
  v_applied_ids     uuid[]  := '{}'::uuid[];
  v_credit          record;
  v_notes           text;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Membresía activa más reciente.
  select * into v_membership
    from public.memberships
   where business_id = p_business_id
     and status = 'active'
   order by created_at desc
   limit 1;

  if v_membership.id is null then
    raise exception 'El negocio % no tiene membresía activa', p_business_id;
  end if;

  v_amount_gross := public.plan_monthly_fee(v_membership.plan_type);
  if v_amount_gross = 0 then
    raise exception 'Plan % sin costo, no se genera factura', v_membership.plan_type
      using errcode = '22023';
  end if;

  -- Período: mes calendario actual en zona DR.
  v_period_start := date_trunc('month', (now() at time zone 'America/Santo_Domingo'))::date;
  v_period_end   := (v_period_start + interval '1 month' - interval '1 day')::date;
  v_due_date     := (v_period_start::timestamptz + interval '15 days');

  -- Idempotencia: si ya existe la del mes, devolverla sin tocar créditos.
  select * into v_invoice
    from public.membership_invoices
   where business_id = p_business_id
     and period_start = v_period_start
   limit 1;
  if v_invoice.id is not null then
    return v_invoice;
  end if;

  -- Aplicar créditos FIFO. Solo enteros (no parciales).
  v_remaining := v_amount_gross;
  for v_credit in
    select id, amount
      from public.admin_extensions
     where business_id          = p_business_id
       and extension_type       = 'free_credit'
       and reverted_at         is null
       and applied_to_invoice_id is null
     order by granted_at asc
  loop
    exit when v_remaining <= 0;
    if v_credit.amount <= v_remaining then
      v_remaining      := v_remaining - v_credit.amount;
      v_total_applied  := v_total_applied + v_credit.amount;
      v_applied_ids    := array_append(v_applied_ids, v_credit.id);
    end if;
    -- Si v_credit.amount > v_remaining, lo dejamos para una factura futura.
  end loop;

  v_amount_net := greatest(0, v_amount_gross - v_total_applied);
  v_itbis      := round(v_amount_net * v_itbis_rate, 2);

  if v_total_applied > 0 then
    v_notes := format(
      'Crédito aplicado: RD$%s sobre %s factura(s) original RD$%s.',
      v_total_applied,
      cardinality(v_applied_ids),
      v_amount_gross
    );
  end if;

  insert into public.membership_invoices (
    business_id, membership_id, plan_type,
    period_start, period_end, due_date,
    amount, itbis,
    status, paid_at, payment_method,
    notes
  )
  values (
    p_business_id, v_membership.id, v_membership.plan_type,
    v_period_start, v_period_end, v_due_date,
    v_amount_net,
    v_itbis,
    -- Si el crédito cubre todo, marcamos paid de una.
    case when v_amount_net = 0 then 'paid' else 'pending' end,
    case when v_amount_net = 0 then now() else null end,
    case when v_amount_net = 0 then 'credit_applied' else null end,
    v_notes
  )
  returning * into v_invoice;

  -- Asociar las extensions consumidas a la factura emitida.
  if cardinality(v_applied_ids) > 0 then
    update public.admin_extensions
       set applied_to_invoice_id = v_invoice.id
     where id = any(v_applied_ids);

    insert into public.noc_audit_log (
      user_id, action, target_resource, target_id, business_id, payload
    )
    values (
      auth.uid(),
      'invoice.credit_applied',
      'membership_invoices',
      v_invoice.id,
      p_business_id,
      jsonb_build_object(
        'credit_total',     v_total_applied,
        'extension_ids',    to_jsonb(v_applied_ids),
        'amount_gross',     v_amount_gross,
        'amount_net',       v_amount_net,
        'auto_paid',        (v_amount_net = 0)
      )
    );
  end if;

  return v_invoice;
end;
$$;

comment on function public.generate_membership_invoice(uuid) is
  'Genera la factura mensual y aplica admin_extensions.free_credit FIFO. Si el crédito cubre 100%%, marca paid automáticamente.';

grant execute on function public.generate_membership_invoice(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- get_business_extensions: agregar `applied_to_invoice_number` para UI.
--
-- Mantiene compat con la versión de 0020 — la columna nueva es additiva.
-- (Postgres no permite ALTER RETURNS TABLE; recreamos.)
-- ---------------------------------------------------------------------------
drop function if exists public.get_business_extensions(uuid);

create or replace function public.get_business_extensions(p_business_id uuid)
returns table (
  id                          uuid,
  business_id                 uuid,
  extension_type              text,
  days_granted                int,
  amount                      numeric,
  currency_code               text,
  reason                      text,
  customer_facing_message     text,
  effective_until             timestamptz,
  previous_end_date           timestamptz,
  granted_by_name             text,
  granted_at                  timestamptz,
  reverted_at                 timestamptz,
  reverted_by_name            text,
  reverted_reason             text,
  applied_to_invoice_id       uuid,
  applied_to_invoice_number   text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return query
  select
    e.id,
    e.business_id,
    e.extension_type,
    e.days_granted,
    e.amount,
    e.currency_code,
    e.reason,
    e.customer_facing_message,
    e.effective_until,
    e.previous_end_date,
    coalesce(gp.full_name, gu.email)             as granted_by_name,
    e.granted_at,
    e.reverted_at,
    coalesce(rp.full_name, ru.email)             as reverted_by_name,
    e.reverted_reason,
    e.applied_to_invoice_id,
    mi.invoice_number                            as applied_to_invoice_number
  from public.admin_extensions e
  left join auth.users     gu on gu.id = e.granted_by
  left join public.profiles gp on gp.id = e.granted_by
  left join auth.users     ru on ru.id = e.reverted_by
  left join public.profiles rp on rp.id = e.reverted_by
  left join public.membership_invoices mi on mi.id = e.applied_to_invoice_id
  where e.business_id = p_business_id
  order by e.granted_at desc;
end;
$$;

grant execute on function public.get_business_extensions(uuid) to authenticated;

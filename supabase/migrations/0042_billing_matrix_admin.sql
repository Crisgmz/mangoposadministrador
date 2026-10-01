-- ============================================================================
-- Migración 0042 — Matriz de facturación (negocio × mes) para la consola.
--
-- La pantalla de Facturación necesitaba responder tres preguntas de un vistazo
-- que hasta ahora exigían abrir negocio por negocio:
--   1) ¿Qué negocios tienen tarjeta agregada y verificada?
--   2) ¿Cuándo se le cobra a cada uno (next_billing_date)?
--   3) ¿Cómo viene el historial de pago mes a mes?
--
-- `admin_billing_matrix` devuelve una fila por negocio con el estado de la
-- suscripción ancla, la tarjeta default, el último cobro y un arreglo de N
-- meses (ventana móvil que termina en el mes en curso) con la factura de cada
-- período. Un solo round-trip para toda la pantalla.
--
-- Solo operadores (`is_platform_operator()`), igual que el resto de 0039.
-- Idempotente.
-- ============================================================================

create or replace function public.admin_billing_matrix(
  p_months int  default 6,
  p_env    text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_months int  := greatest(1, least(coalesce(p_months, 6), 24));
  v_today  date := (now() at time zone 'America/Santo_Domingo')::date;
  v_first  date := (date_trunc('month', v_today)
                     - make_interval(months => v_months - 1))::date;
  v_last   date := date_trunc('month', v_today)::date;
  v_result jsonb;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_env is not null and p_env not in ('production', 'sandbox') then
    raise exception 'Entorno inválido: %', p_env using errcode = '22023';
  end if;

  with months as (
    select gs::date as period_start
      from generate_series(v_first::timestamp, v_last::timestamp, interval '1 month') gs
  ),
  biz as (
    select b.id, b.business_name, b.domain, b.environment, b.status
      from public.businesses b
     where (p_env is null or b.environment = p_env)
  ),
  -- Membresía ancla del negocio. Si ninguna está marcada como ancla, caemos a
  -- la del owner más reciente: es la misma preferencia que usa
  -- admin_update_subscription_billing al promover una.
  anchor as (
    select distinct on (m.business_id)
           m.business_id,
           m.id as membership_id,
           m.is_billing_anchor,
           m.billing_status,
           m.plan_type,
           m.plan_id,
           m.trial_ends_at,
           m.next_billing_date,
           m.current_period_start,
           m.current_period_end,
           m.current_attempt_number,
           m.consent_granted_at,
           m.suspended_at,
           m.cancelled_at
      from public.memberships m
     order by m.business_id,
              m.is_billing_anchor desc nulls last,
              (m.role = 'owner') desc,
              m.created_at desc
  )
  select coalesce(jsonb_agg(row_json order by business_name), '[]'::jsonb)
    into v_result
  from (
    select
      bz.business_name,
      jsonb_build_object(
        'business_id',            bz.id,
        'business_name',          bz.business_name,
        'domain',                 bz.domain,
        'environment',            bz.environment,
        'business_status',        bz.status,
        'membership_id',          a.membership_id,
        'is_billing_anchor',      coalesce(a.is_billing_anchor, false),
        'billing_status',         a.billing_status,
        'plan_type',              a.plan_type,
        'plan_code',              p.code,
        'plan_name',              p.name,
        'currency_code',          p.currency_code,
        -- Tarifa mensual de referencia: el catálogo de planes manda; si la
        -- membresía es legacy (sin plan_id) caemos a la tabla de tarifas.
        'monthly_fee',            coalesce(
                                    p.price_cents_monthly / 100.0,
                                    public.plan_monthly_fee(a.plan_type)
                                  ),
        'trial_ends_at',          a.trial_ends_at,
        'next_billing_date',      a.next_billing_date,
        'current_period_start',   a.current_period_start,
        'current_period_end',     a.current_period_end,
        'current_attempt_number', coalesce(a.current_attempt_number, 0),
        'consent_granted_at',     a.consent_granted_at,
        'suspended_at',           a.suspended_at,
        'cancelled_at',           a.cancelled_at,
        'cards_count', (
          select count(*)
            from public.azul_payment_methods pm
           where pm.business_id = bz.id
        ),
        'card', (
          select jsonb_build_object(
                   'brand',      pm.data_vault_brand,
                   'masked',     pm.card_number_masked,
                   'status',     pm.status,
                   'expiration', pm.data_vault_expiration
                 )
            from public.azul_payment_methods pm
           where pm.business_id = bz.id
             and pm.is_default = true
           limit 1
        ),
        'last_charge', (
          select jsonb_build_object(
                   'status',           c.status,
                   'amount_cents',     c.amount_cents,
                   'attempted_at',     c.attempted_at,
                   'response_message', c.response_message
                 )
            from public.azul_charges c
           where c.membership_id = a.membership_id
           order by c.attempted_at desc nulls last
           limit 1
        ),
        'months', (
          select jsonb_agg(
                   jsonb_build_object(
                     'period_start',   mo.period_start,
                     'invoice_id',     i.id,
                     'invoice_number', i.invoice_number,
                     'status',         coalesce(i.status, 'none'),
                     'total',          i.total,
                     'due_date',       i.due_date,
                     'paid_at',        i.paid_at,
                     'payment_method', i.payment_method
                   )
                   order by mo.period_start
                 )
            from months mo
            left join lateral (
              select mi.*
                from public.membership_invoices mi
               where mi.business_id = bz.id
                 and mi.period_start >= mo.period_start
                 and mi.period_start <  (mo.period_start + interval '1 month')
               order by (mi.status = 'paid') desc, mi.issue_date desc
               limit 1
            ) i on true
        )
      ) as row_json
      from biz bz
      left join anchor a on a.business_id = bz.id
      left join public.plans p on p.id = a.plan_id
  ) t;

  return v_result;
end;
$$;

comment on function public.admin_billing_matrix(int, text) is
  'Matriz de facturación negocio × mes: suscripción ancla, tarjeta default, último cobro y estado de la factura de cada uno de los últimos N meses. Solo operadores.';

grant execute on function public.admin_billing_matrix(int, text) to authenticated;

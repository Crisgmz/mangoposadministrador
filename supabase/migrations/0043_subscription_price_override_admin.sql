-- ============================================================================
-- Migración 0043 — Precio especial por cliente (consola).
--
-- Permite fijarle a un negocio un precio mensual menor al de lista para su
-- plan actual —p.ej. Pro a RD$3,000 en vez de RD$4,799— y hace que TODO lo que
-- factura o reporta dinero en la consola respete ese precio.
--
-- DEPENDE de mangospos/supabase/migrations/20260915_0006_subscription_price_override.sql
-- (columnas en memberships + funciones de precio efectivo). El bloque 0 aborta
-- con un mensaje claro si no está aplicada.
--
--   0) guard de dependencia
--   1) admin_set_price_override(business, precio, razón, vence?)   → jsonb
--   2) admin_clear_price_override(business, razón)                 → jsonb
--   3) admin_get_business_billing  — + precio especial / efectivo / razón
--   4) generate_membership_invoice — factura con el precio efectivo
--   5) get_billing_metrics         — MRR con el precio efectivo
--   6) admin_billing_matrix        — monthly_fee efectivo (+ lista y marca)
--
-- Todo gateado por is_platform_operator(). Set/clear auditan en noc_audit_log
-- con razón obligatoria: es el único lugar donde queda POR QUÉ un cliente paga
-- menos (la fila de memberships la lee la app del cliente y no debe mostrarlo).
-- Idempotente.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0) Guard
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.subscription_effective_price_cents(uuid,date)') is null
     or to_regprocedure('public.business_price_override_cents(uuid,text,date)') is null then
    raise exception
      'Falta mangospos 20260915_0006_subscription_price_override.sql. Aplicarla antes que 0043.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1) admin_set_price_override
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_price_override(
  p_business_id   uuid,
  p_price_monthly numeric,
  p_reason        text,
  p_ends_on       date default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_reason     text := trim(coalesce(p_reason, ''));
  v_today      date := (now() at time zone 'America/Santo_Domingo')::date;
  v_membership public.memberships;
  v_plan       public.plans;
  v_cents      integer;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_reason = '' then
    raise exception 'La razón es obligatoria' using errcode = '22023';
  end if;

  if p_price_monthly is null or p_price_monthly <= 0 then
    raise exception 'El precio especial debe ser mayor que cero' using errcode = '22023';
  end if;

  if p_ends_on is not null and p_ends_on < v_today then
    raise exception 'La fecha de vencimiento no puede estar en el pasado' using errcode = '22023';
  end if;

  select * into v_membership
    from public.memberships
   where business_id = p_business_id
     and is_billing_anchor = true
   limit 1;

  if v_membership.id is null then
    raise exception 'El negocio no tiene suscripción configurada. Configúrala antes de darle un precio especial.'
      using errcode = 'P0001';
  end if;

  select * into v_plan from public.plans where id = v_membership.plan_id;
  if v_plan.id is null then
    raise exception 'La suscripción no tiene plan asignado.' using errcode = 'P0001';
  end if;

  v_cents := round(p_price_monthly * 100)::int;

  -- Un precio especial es un descuento. Igual o por encima de la lista no
  -- tiene sentido y casi siempre es un error de tipeo (47990 por 4799).
  if v_cents >= v_plan.price_cents_monthly then
    raise exception 'El precio especial (RD$%) debe ser menor al precio de lista de % (RD$%)',
      to_char(v_cents / 100.0, 'FM999,999,990.00'),
      v_plan.name,
      to_char(v_plan.price_cents_monthly / 100.0, 'FM999,999,990.00')
      using errcode = '22023';
  end if;

  update public.memberships
     set price_override_cents   = v_cents,
         price_override_plan_id = v_plan.id,
         price_override_ends_on = p_ends_on
   where id = v_membership.id;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'subscription.price_override_set',
    'memberships',
    v_membership.id,
    p_business_id,
    jsonb_build_object(
      'reason',           v_reason,
      'plan_code',        v_plan.code,
      'list_price_cents', v_plan.price_cents_monthly,
      'before', jsonb_build_object(
        'price_override_cents',   v_membership.price_override_cents,
        'price_override_plan_id', v_membership.price_override_plan_id,
        'price_override_ends_on', v_membership.price_override_ends_on
      ),
      'after', jsonb_build_object(
        'price_override_cents',   v_cents,
        'price_override_plan_id', v_plan.id,
        'price_override_ends_on', p_ends_on
      )
    )
  );

  return public.admin_get_business_billing(p_business_id);
end;
$$;

comment on function public.admin_set_price_override(uuid, numeric, text, date) is
  'Fija un precio mensual especial (menor al de lista) para el plan actual de la suscripción del negocio. Solo operadores; audita en noc_audit_log.';

grant execute on function public.admin_set_price_override(uuid, numeric, text, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) admin_clear_price_override
-- ---------------------------------------------------------------------------
create or replace function public.admin_clear_price_override(
  p_business_id uuid,
  p_reason      text
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_reason     text := trim(coalesce(p_reason, ''));
  v_membership public.memberships;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_reason = '' then
    raise exception 'La razón es obligatoria' using errcode = '22023';
  end if;

  select * into v_membership
    from public.memberships
   where business_id = p_business_id
     and is_billing_anchor = true
   limit 1;

  if v_membership.id is null or v_membership.price_override_cents is null then
    raise exception 'Este negocio no tiene precio especial.' using errcode = 'P0001';
  end if;

  update public.memberships
     set price_override_cents   = null,
         price_override_plan_id = null,
         price_override_ends_on = null
   where id = v_membership.id;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'subscription.price_override_cleared',
    'memberships',
    v_membership.id,
    p_business_id,
    jsonb_build_object(
      'reason', v_reason,
      'before', jsonb_build_object(
        'price_override_cents',   v_membership.price_override_cents,
        'price_override_plan_id', v_membership.price_override_plan_id,
        'price_override_ends_on', v_membership.price_override_ends_on
      )
    )
  );

  return public.admin_get_business_billing(p_business_id);
end;
$$;

comment on function public.admin_clear_price_override(uuid, text) is
  'Quita el precio especial de la suscripción del negocio (vuelve al precio de lista). Solo operadores; audita en noc_audit_log.';

grant execute on function public.admin_clear_price_override(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) admin_get_business_billing — igual que 0039 + precio especial.
--
--    `effective_price_cents` y `price_override_applies` se evalúan en la fecha
--    del PRÓXIMO COBRO (o hoy si no hay): eso es lo que le importa ver al
--    operador — cuánto se le va a cobrar, no cuánto costaría hoy.
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_business_billing(
  p_business_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_today  date := (now() at time zone 'America/Santo_Domingo')::date;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'membership_id',          m.id,
    'business_id',            m.business_id,
    'billing_status',         m.billing_status,
    'plan_code',              p.code,
    'plan_name',              p.name,
    'price_cents_monthly',    p.price_cents_monthly,
    'currency_code',          p.currency_code,
    'trial_ends_at',          m.trial_ends_at,
    'current_period_start',   m.current_period_start,
    'current_period_end',     m.current_period_end,
    'next_billing_date',      m.next_billing_date,
    'current_attempt_number', m.current_attempt_number,
    'consent_granted_at',     m.consent_granted_at,
    'suspended_at',           m.suspended_at,
    'cancelled_at',           m.cancelled_at,
    'cancellation_reason',    m.cancellation_reason,
    'price_override_cents',   m.price_override_cents,
    'price_override_ends_on', m.price_override_ends_on,
    'price_override_plan_code', (
      select op.code from public.plans op where op.id = m.price_override_plan_id
    ),
    'price_override_applies',
      public.subscription_price_override_cents(
        m.id, coalesce(m.next_billing_date, v_today)
      ) is not null,
    'effective_price_cents',
      public.subscription_effective_price_cents(
        m.id, coalesce(m.next_billing_date, v_today)
      ),
    'price_override_reason', case
      when m.price_override_cents is null then null
      else (
        select l.payload->>'reason'
          from public.noc_audit_log l
         where l.target_id = m.id
           and l.action = 'subscription.price_override_set'
         order by l.created_at desc
         limit 1
      )
    end,
    'price_override_set_at', case
      when m.price_override_cents is null then null
      else (
        select l.created_at
          from public.noc_audit_log l
         where l.target_id = m.id
           and l.action = 'subscription.price_override_set'
         order by l.created_at desc
         limit 1
      )
    end,
    'card', (
      select jsonb_build_object(
        'brand',      pm.data_vault_brand,
        'masked',     pm.card_number_masked,
        'status',     pm.status,
        'expiration', pm.data_vault_expiration
      )
      from public.azul_payment_methods pm
      where pm.business_id = m.business_id
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
      where c.membership_id = m.id
      order by c.attempted_at desc nulls last
      limit 1
    )
  )
  into v_result
  from public.memberships m
  left join public.plans p on p.id = m.plan_id
  where m.business_id = p_business_id
    and m.is_billing_anchor = true
  limit 1;

  return v_result;
end;
$$;

comment on function public.admin_get_business_billing(uuid) is
  'Estado de suscripción/cobro automático (Azul) del negocio: membresía ancla + plan + precio especial/efectivo + tarjeta default + último cobro. Solo operadores.';

grant execute on function public.admin_get_business_billing(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) generate_membership_invoice — igual que 0033, con precio efectivo.
--
--    El período se calcula ANTES del monto: el vencimiento del precio especial
--    se evalúa contra el período que se factura.
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
  v_list_amount     numeric;
  v_override_cents  integer;
  v_amount_gross    numeric;
  v_amount_net      numeric;
  v_itbis_rate      numeric := 0.18;
  v_itbis           numeric;
  v_tax_included    boolean;
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

  select * into v_membership
    from public.memberships
   where business_id = p_business_id
     and status = 'active'
   order by created_at desc
   limit 1;

  if v_membership.id is null then
    raise exception 'El negocio % no tiene membresía activa', p_business_id;
  end if;

  v_period_start := coalesce(
    (v_membership.end_date at time zone 'America/Santo_Domingo')::date,
    (now() at time zone 'America/Santo_Domingo')::date
  );
  v_period_end := (v_period_start + interval '1 month' - interval '1 day')::date;
  v_due_date   := v_period_start::timestamptz;

  v_list_amount := public.plan_monthly_fee(v_membership.plan_type);
  if v_list_amount = 0 then
    raise exception 'Plan % sin costo, no se genera factura', v_membership.plan_type
      using errcode = '22023';
  end if;

  -- Precio especial del negocio para ESTE plan en ESTE período. least() con la
  -- lista del catálogo: nunca facturar por encima de lo que cuesta el plan.
  v_override_cents := public.business_price_override_cents(
    p_business_id, v_membership.plan_type, v_period_start
  );
  v_amount_gross := case
    when v_override_cents is null then v_list_amount
    else least(v_override_cents / 100.0, v_list_amount)
  end;

  -- Leer tax_included del plan. Si el plan no existe en catálogo (legacy),
  -- asumimos true (inclusivo) como default seguro.
  select coalesce(tax_included, true) into v_tax_included
    from public.plan_catalog
   where code = v_membership.plan_type;
  v_tax_included := coalesce(v_tax_included, true);

  select * into v_invoice
    from public.membership_invoices
   where business_id = p_business_id
     and period_start = v_period_start
   limit 1;
  if v_invoice.id is not null then
    return v_invoice;
  end if;

  -- free_credit FIFO.
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
  end loop;

  v_amount_net := greatest(0, v_amount_gross - v_total_applied);

  if v_tax_included then
    v_itbis := 0;
  else
    v_itbis := round(v_amount_net * v_itbis_rate, 2);
  end if;

  -- La nota deja rastro del precio especial EN la factura: quien la lea meses
  -- después tiene que entender por qué no coincide con el precio del plan.
  if v_amount_gross < v_list_amount then
    v_notes := format(
      'Precio especial RD$%s (lista RD$%s).',
      to_char(v_amount_gross, 'FM999,999,990.00'),
      to_char(v_list_amount, 'FM999,999,990.00')
    );
  end if;

  if v_total_applied > 0 then
    v_notes := coalesce(v_notes || ' ', '') || format(
      'Crédito aplicado: RD$%s sobre %s factura(s) original RD$%s.',
      v_total_applied,
      cardinality(v_applied_ids),
      v_amount_gross
    );
  end if;

  if v_tax_included then
    v_notes := coalesce(v_notes || ' ', '') || 'Precio incluye ITBIS.';
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
    case when v_amount_net = 0 then 'paid' else 'pending' end,
    case when v_amount_net = 0 then now() else null end,
    case when v_amount_net = 0 then 'credit_applied' else null end,
    v_notes
  )
  returning * into v_invoice;

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
        'credit_total',  v_total_applied,
        'extension_ids', to_jsonb(v_applied_ids),
        'amount_gross',  v_amount_gross,
        'amount_net',    v_amount_net,
        'auto_paid',     (v_amount_net = 0)
      )
    );
  end if;

  return v_invoice;
end;
$$;

grant execute on function public.generate_membership_invoice(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) get_billing_metrics — igual que 0006, MRR con precio efectivo.
--    LEAST ignora NULL: sin precio especial queda la tarifa de lista.
-- ---------------------------------------------------------------------------
create or replace function public.get_billing_metrics(p_env text default null)
returns table (
  mrr             numeric,
  total_paid      numeric,
  total_pending   numeric,
  total_expired   numeric,
  count_pending   int,
  count_expired   int
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
  with filtered_biz as (
    select id from public.businesses
     where p_env is null or environment = p_env
  ),
  mrr_calc as (
    select coalesce(sum(
             least(
               public.business_price_override_cents(lm.business_id, lm.plan_type) / 100.0,
               public.plan_monthly_fee(lm.plan_type)
             )
           ), 0) as mrr_amount
      from (
        select distinct on (m.business_id)
               m.business_id, m.plan_type
          from public.memberships m
          join public.businesses b on b.id = m.business_id
         where m.status = 'active'
           and b.status = 'active'
           and (p_env is null or b.environment = p_env)
         order by m.business_id, m.created_at desc
      ) lm
  )
  select
    (select mrr_amount from mrr_calc)::numeric                                as mrr,
    coalesce(sum(mi.total) filter (where mi.status = 'paid'), 0)::numeric     as total_paid,
    coalesce(sum(mi.total) filter (where mi.status = 'pending'), 0)::numeric  as total_pending,
    coalesce(sum(mi.total) filter (where mi.status = 'expired'), 0)::numeric  as total_expired,
    coalesce(count(*) filter (where mi.status = 'pending'), 0)::int           as count_pending,
    coalesce(count(*) filter (where mi.status = 'expired'), 0)::int           as count_expired
  from public.membership_invoices mi
  where p_env is null
     or mi.business_id in (select id from filtered_biz);
end;
$$;

grant execute on function public.get_billing_metrics(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) admin_billing_matrix — igual que 0042, con monthly_fee efectivo.
--    Agrega list_monthly_fee y has_price_override para que la UI pueda marcar
--    a los clientes con precio especial.
-- ---------------------------------------------------------------------------
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
        -- Tarifa que se le va a cobrar en su próximo cobro: precio especial si
        -- tiene uno vigente; si no, catálogo de planes; si la membresía es
        -- legacy (sin plan_id), tabla de tarifas.
        'monthly_fee',            coalesce(
                                    public.subscription_effective_price_cents(
                                      a.membership_id,
                                      coalesce(a.next_billing_date, v_today)
                                    ) / 100.0,
                                    p.price_cents_monthly / 100.0,
                                    public.plan_monthly_fee(a.plan_type)
                                  ),
        'list_monthly_fee',       coalesce(
                                    p.price_cents_monthly / 100.0,
                                    public.plan_monthly_fee(a.plan_type)
                                  ),
        'has_price_override',     public.subscription_price_override_cents(
                                    a.membership_id,
                                    coalesce(a.next_billing_date, v_today)
                                  ) is not null,
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
  'Matriz de facturación negocio × mes: suscripción ancla, precio efectivo (con precio especial), tarjeta default, último cobro y estado de la factura de cada uno de los últimos N meses. Solo operadores.';

grant execute on function public.admin_billing_matrix(int, text) to authenticated;

commit;

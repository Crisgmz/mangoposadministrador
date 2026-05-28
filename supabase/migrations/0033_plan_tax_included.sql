-- ---------------------------------------------------------------------------
-- 0033_plan_tax_included.sql
--
-- Cambios en facturación de membresías:
--
--   1) `plan_catalog` adquiere `tax_included` (default true). Cuando true,
--      el `price_monthly` ya incluye ITBIS — la factura NO desglosa
--      impuesto, sale como una sola línea.
--
--   2) `generate_membership_invoice` respeta `tax_included`:
--      * tax_included=true  → itbis=0, amount = price (sin extra)
--      * tax_included=false → itbis = round(amount * 0.18), amount = price
--
--   3) `admin_upsert_plan` acepta `p_tax_included`.
--   4) `admin_get_plans` devuelve `tax_included`.
--
-- Default `true` porque el usuario pidió que los planes sean inclusivos.
-- Para activar desglose de impuesto en un plan específico, marcar
-- `tax_included=false` desde la UI.
-- ---------------------------------------------------------------------------

-- 1) Schema change.
alter table public.plan_catalog
  add column if not exists tax_included boolean not null default true;

comment on column public.plan_catalog.tax_included is
  'Si true, price_monthly ya incluye ITBIS y la factura no desglosa impuesto.';


-- 2) generate_membership_invoice respeta tax_included.
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

  v_amount_gross := public.plan_monthly_fee(v_membership.plan_type);
  if v_amount_gross = 0 then
    raise exception 'Plan % sin costo, no se genera factura', v_membership.plan_type
      using errcode = '22023';
  end if;

  -- Leer tax_included del plan. Si el plan no existe en catálogo (legacy),
  -- asumimos true (inclusivo) como default seguro.
  select coalesce(tax_included, true) into v_tax_included
    from public.plan_catalog
   where code = v_membership.plan_type;
  v_tax_included := coalesce(v_tax_included, true);

  v_period_start := coalesce(
    (v_membership.end_date at time zone 'America/Santo_Domingo')::date,
    (now() at time zone 'America/Santo_Domingo')::date
  );
  v_period_end := (v_period_start + interval '1 month' - interval '1 day')::date;
  v_due_date   := v_period_start::timestamptz;

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

  -- Aquí el cambio clave: ITBIS solo si el plan NO es inclusivo.
  if v_tax_included then
    v_itbis := 0;
  else
    v_itbis := round(v_amount_net * v_itbis_rate, 2);
  end if;

  if v_total_applied > 0 then
    v_notes := format(
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


-- 3) admin_upsert_plan acepta p_tax_included.
drop function if exists public.admin_upsert_plan(text, text, text, numeric, jsonb, int, boolean);

create or replace function public.admin_upsert_plan(
  p_code          text,
  p_name          text,
  p_description   text,
  p_price_monthly numeric,
  p_features      jsonb,
  p_display_order int,
  p_is_active     boolean default true,
  p_tax_included  boolean default true
)
returns public.plan_catalog
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_plan   public.plan_catalog;
  v_before public.plan_catalog;
  v_code   text := lower(trim(coalesce(p_code, '')));
  v_name   text := trim(coalesce(p_name, ''));
  v_is_new boolean;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_code = '' or v_code !~ '^[a-z][a-z0-9_]*$' then
    raise exception 'Code inválido: usa minúsculas, números y underscore (ej: pro_plus).'
      using errcode = '22023';
  end if;
  if v_name = '' then
    raise exception 'El nombre es obligatorio.' using errcode = '22023';
  end if;
  if p_price_monthly is null or p_price_monthly < 0 then
    raise exception 'Precio inválido (debe ser >= 0).' using errcode = '22023';
  end if;

  select * into v_before from public.plan_catalog where code = v_code;
  v_is_new := v_before.code is null;

  insert into public.plan_catalog (
    code, name, description, price_monthly,
    features, display_order, is_active, tax_included,
    updated_at, updated_by
  )
  values (
    v_code, v_name, nullif(trim(coalesce(p_description, '')), ''),
    p_price_monthly,
    coalesce(p_features, '[]'::jsonb),
    coalesce(p_display_order, 0),
    coalesce(p_is_active, true),
    coalesce(p_tax_included, true),
    now(), auth.uid()
  )
  on conflict (code) do update
    set name           = excluded.name,
        description    = excluded.description,
        price_monthly  = excluded.price_monthly,
        features       = excluded.features,
        display_order  = excluded.display_order,
        is_active      = excluded.is_active,
        tax_included   = excluded.tax_included,
        updated_at     = now(),
        updated_by     = auth.uid()
  returning * into v_plan;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, payload
  )
  values (
    auth.uid(),
    case when v_is_new then 'plan.create' else 'plan.update' end,
    'plan_catalog',
    null,
    jsonb_build_object(
      'code', v_code,
      'before', case when v_is_new then null else to_jsonb(v_before) end,
      'after',  to_jsonb(v_plan)
    )
  );

  return v_plan;
end;
$$;

grant execute on function public.admin_upsert_plan(text, text, text, numeric, jsonb, int, boolean, boolean)
  to authenticated;


-- 4) admin_get_plans devuelve tax_included.
drop function if exists public.admin_get_plans();

create or replace function public.admin_get_plans()
returns table (
  code               text,
  name               text,
  description        text,
  price_monthly      numeric,
  currency_code      text,
  features           jsonb,
  display_order      int,
  is_active          boolean,
  tax_included       boolean,
  archived_at        timestamptz,
  archived_reason    text,
  active_subscribers int,
  created_at         timestamptz,
  updated_at         timestamptz
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
    p.code,
    p.name,
    p.description,
    p.price_monthly,
    p.currency_code,
    p.features,
    p.display_order,
    p.is_active,
    p.tax_included,
    p.archived_at,
    p.archived_reason,
    (select count(*)::int
       from public.memberships m
      where m.plan_type = p.code
        and m.status    = 'active')         as active_subscribers,
    p.created_at,
    p.updated_at
  from public.plan_catalog p
  order by p.archived_at nulls first, p.display_order, p.code;
end;
$$;

grant execute on function public.admin_get_plans() to authenticated;


notify pgrst, 'reload schema';

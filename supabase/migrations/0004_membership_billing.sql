-- ============================================================================
-- Migración 0004 — Facturación de membresías (Fase 3 del PRD)
--
-- Schema y RPCs que la consola usa para cobrar mensualmente a cada negocio
-- por su plan. Es independiente de la facturación fiscal de DGII (`fiscal_documents`),
-- que es la que emite cada negocio a sus propios clientes.
--
-- Solo los operadores de plataforma pueden leer/escribir esta data.
-- Aplicar contra el mismo proyecto Supabase de `mangospos`. Idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Helpers de pricing y numeración
-- ---------------------------------------------------------------------------

-- Tarifa mensual por plan (RD$, sin ITBIS). Editar aquí si cambian los precios.
create or replace function public.plan_monthly_fee(p_plan text)
returns numeric
language sql
immutable
as $$
  select case p_plan
    when 'pro'   then 2490::numeric
    when 'basic' then  990::numeric
    when 'free'  then    0::numeric
    when 'trial' then    0::numeric
    else                 0::numeric
  end;
$$;

comment on function public.plan_monthly_fee(text) is
  'Tarifa mensual del plan (RD$, sin ITBIS). Cambiar aquí para ajustar precios.';

create sequence if not exists public.membership_invoice_number_seq start 1;

create or replace function public.next_membership_invoice_number()
returns text
language plpgsql
as $$
declare
  v_year int := extract(year from now() at time zone 'America/Santo_Domingo')::int;
  v_seq  int := nextval('public.membership_invoice_number_seq');
begin
  return format('MNG-%s-%s', v_year, lpad(v_seq::text, 5, '0'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Tabla `membership_invoices`
-- ---------------------------------------------------------------------------
create table if not exists public.membership_invoices (
  id                uuid primary key default gen_random_uuid(),
  business_id       uuid not null references public.businesses(id) on delete restrict,
  membership_id     uuid references public.memberships(id) on delete set null,
  invoice_number    text not null unique default public.next_membership_invoice_number(),
  plan_type         text not null check (plan_type in ('trial', 'free', 'basic', 'pro')),
  period_start      date not null,
  period_end        date not null,
  issue_date        timestamptz not null default now(),
  due_date          timestamptz not null,
  amount            numeric(12,2) not null check (amount >= 0),
  itbis             numeric(12,2) not null default 0 check (itbis >= 0),
  total             numeric(12,2) generated always as (amount + itbis) stored,
  status            text not null default 'pending'
                    check (status in ('pending', 'paid', 'expired', 'void')),
  paid_at           timestamptz,
  paid_by           uuid references auth.users(id),
  payment_method    text,
  payment_reference text,
  voided_at         timestamptz,
  voided_by         uuid references auth.users(id),
  void_reason       text,
  notes             text,
  created_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id) default auth.uid(),
  unique (business_id, period_start)
);

comment on table public.membership_invoices is
  'Facturas mensuales de membresía que cobra MangoPOS a cada negocio. NO es facturación fiscal DGII.';

create index if not exists membership_invoices_business_idx
  on public.membership_invoices (business_id, issue_date desc);
create index if not exists membership_invoices_status_idx
  on public.membership_invoices (status, due_date);

-- RLS: solo operadores de plataforma.
alter table public.membership_invoices enable row level security;

drop policy if exists "membership_invoices operators only" on public.membership_invoices;
create policy "membership_invoices operators only"
on public.membership_invoices
for all
to authenticated
using (public.is_platform_operator())
with check (public.is_platform_operator());

-- ---------------------------------------------------------------------------
-- 3) RPC: get_billing_overview()
--    Lista de facturas con info del negocio, lista para la pantalla.
-- ---------------------------------------------------------------------------
create or replace function public.get_billing_overview()
returns table (
  id              uuid,
  invoice_number  text,
  business_id     uuid,
  business_name   text,
  plan_type       text,
  period_start    date,
  period_end      date,
  issue_date      timestamptz,
  due_date        timestamptz,
  amount          numeric,
  itbis           numeric,
  total           numeric,
  status          text,
  paid_at         timestamptz,
  payment_method  text,
  payment_reference text
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
  select i.id, i.invoice_number, i.business_id, b.business_name,
         i.plan_type, i.period_start, i.period_end,
         i.issue_date, i.due_date,
         i.amount, i.itbis, i.total,
         i.status, i.paid_at, i.payment_method, i.payment_reference
    from public.membership_invoices i
    join public.businesses b on b.id = i.business_id
   order by i.issue_date desc;
end;
$$;

grant execute on function public.get_billing_overview() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) RPC: get_billing_metrics()
--    MRR + cobrado + pendiente + vencido en un solo round-trip.
-- ---------------------------------------------------------------------------
create or replace function public.get_billing_metrics()
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
  with mrr_calc as (
    -- Usamos alias `mrr_amount` (no `mrr`) para evitar choque con la
    -- columna de salida de la función, que también se llama `mrr`.
    select coalesce(sum(public.plan_monthly_fee(lm.plan_type)), 0) as mrr_amount
      from (
        select distinct on (m.business_id)
               m.business_id, m.plan_type
          from public.memberships m
          join public.businesses b on b.id = m.business_id
         where m.status = 'active'
           and b.status = 'active'
         order by m.business_id, m.created_at desc
      ) lm
  )
  select
    (select mrr_amount from mrr_calc)::numeric                            as mrr,
    coalesce(sum(mi.total) filter (where mi.status = 'paid'), 0)::numeric as total_paid,
    coalesce(sum(mi.total) filter (where mi.status = 'pending'), 0)::numeric as total_pending,
    coalesce(sum(mi.total) filter (where mi.status = 'expired'), 0)::numeric as total_expired,
    coalesce(count(*) filter (where mi.status = 'pending'), 0)::int       as count_pending,
    coalesce(count(*) filter (where mi.status = 'expired'), 0)::int       as count_expired
  from public.membership_invoices mi;
end;
$$;

grant execute on function public.get_billing_metrics() to authenticated;

-- ---------------------------------------------------------------------------
-- 5) RPC: generate_membership_invoice(p_business_id)
--    Genera (idempotente) la factura del MES ACTUAL para un negocio. Si ya
--    existe una factura con el mismo `period_start`, retorna la existente.
--    Falla si el plan no tiene costo (free/trial).
-- ---------------------------------------------------------------------------
create or replace function public.generate_membership_invoice(p_business_id uuid)
returns public.membership_invoices
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_membership   public.memberships;
  v_period_start date;
  v_period_end   date;
  v_due_date     timestamptz;
  v_amount       numeric;
  v_itbis_rate   numeric := 0.18;
  v_invoice      public.membership_invoices;
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

  if v_membership is null then
    raise exception 'El negocio % no tiene membresía activa', p_business_id;
  end if;

  v_amount := public.plan_monthly_fee(v_membership.plan_type);
  if v_amount = 0 then
    raise exception 'Plan % sin costo, no se genera factura', v_membership.plan_type
      using errcode = '22023';
  end if;

  -- Mes calendario actual en zona DR.
  v_period_start := date_trunc('month', (now() at time zone 'America/Santo_Domingo'))::date;
  v_period_end   := (v_period_start + interval '1 month' - interval '1 day')::date;
  v_due_date     := (v_period_start::timestamptz + interval '15 days');

  -- Idempotencia: si ya existe la del mes, devolverla.
  select * into v_invoice
    from public.membership_invoices
   where business_id = p_business_id
     and period_start = v_period_start
   limit 1;
  if v_invoice.id is not null then
    return v_invoice;
  end if;

  insert into public.membership_invoices (
    business_id, membership_id, plan_type,
    period_start, period_end, due_date,
    amount, itbis
  )
  values (
    p_business_id, v_membership.id, v_membership.plan_type,
    v_period_start, v_period_end, v_due_date,
    v_amount, round(v_amount * v_itbis_rate, 2)
  )
  returning * into v_invoice;

  return v_invoice;
end;
$$;

grant execute on function public.generate_membership_invoice(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) RPC: mark_invoice_paid(p_invoice_id, p_method, p_reference)
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
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  update public.membership_invoices
     set status = 'paid',
         paid_at = now(),
         paid_by = auth.uid(),
         payment_method = p_method,
         payment_reference = coalesce(p_reference, payment_reference)
   where id = p_invoice_id
     and status in ('pending', 'expired')
  returning * into v_invoice;

  if v_invoice.id is null then
    raise exception 'Factura % no existe o no se puede marcar como pagada', p_invoice_id;
  end if;

  return v_invoice;
end;
$$;

grant execute on function public.mark_invoice_paid(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7) RPC: void_invoice(p_invoice_id, p_reason)
-- ---------------------------------------------------------------------------
create or replace function public.void_invoice(p_invoice_id uuid, p_reason text)
returns public.membership_invoices
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_invoice public.membership_invoices;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  update public.membership_invoices
     set status = 'void',
         voided_at = now(),
         voided_by = auth.uid(),
         void_reason = p_reason
   where id = p_invoice_id
     and status <> 'void'
  returning * into v_invoice;

  if v_invoice.id is null then
    raise exception 'Factura % no existe o ya está anulada', p_invoice_id;
  end if;

  return v_invoice;
end;
$$;

grant execute on function public.void_invoice(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8) RPC: expire_overdue_invoices()
--    Marca como `expired` las facturas pending cuya `due_date` ya pasó.
--    Útil para correr en cron / al cargar la pantalla.
-- ---------------------------------------------------------------------------
create or replace function public.expire_overdue_invoices()
returns int
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  update public.membership_invoices
     set status = 'expired'
   where status = 'pending'
     and due_date < now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.expire_overdue_invoices() to authenticated;

-- ---------------------------------------------------------------------------
-- 9) RPC: get_business_invoices(p_business_id)
-- ---------------------------------------------------------------------------
create or replace function public.get_business_invoices(p_business_id uuid)
returns setof public.membership_invoices
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
  select *
    from public.membership_invoices
   where business_id = p_business_id
   order by issue_date desc;
end;
$$;

grant execute on function public.get_business_invoices(uuid) to authenticated;

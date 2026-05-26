-- ---------------------------------------------------------------------------
-- 0025_plan_catalog.sql
--
-- Catálogo editable de planes. Hasta hoy, el precio mensual de cada plan
-- vivía hardcoded en `public.plan_monthly_fee(text)` y los códigos válidos
-- en check constraints sobre `memberships.plan_type` / `membership_invoices.plan_type`.
-- Eso hace imposible editar precios o agregar planes sin migraciones.
--
-- Esta migración:
--   1) Crea tabla `plan_catalog` (PK = code).
--   2) Seedea trial/free/basic/pro con los precios actuales (0/0/990/2490).
--   3) Drop de los check constraints en memberships / membership_invoices y
--      reemplazo por FK a `plan_catalog(code)`. Los valores existentes
--      siguen siendo válidos porque el seed los contempla.
--   4) Reescribe `plan_monthly_fee(text)` para leer de la tabla (cae a 0
--      si el plan no existe, igual que antes).
--   5) RPCs:
--      - get_plans()
--      - upsert_plan(code, name, description, price, features, display_order, is_active)
--      - archive_plan(code, reason)  → bloquea si hay suscriptores activos
--      - restore_plan(code)
--
-- Nota: los precios se almacenan en `numeric(12,2)` (RD$ con centavos),
-- consistente con `membership_invoices.amount`. Esto NO es "locked pricing"
-- (que congelaría el precio del cliente al firmar) — eso es siguiente fase.
-- ---------------------------------------------------------------------------

create table if not exists public.plan_catalog (
  code             text primary key
                   check (length(trim(code)) > 0 and code = lower(code)),
  name             text not null check (length(trim(name)) > 0),
  description      text,
  price_monthly    numeric(12,2) not null default 0 check (price_monthly >= 0),
  currency_code    text not null default 'DOP',
  features         jsonb not null default '[]'::jsonb,
  display_order    int not null default 0,
  is_active        boolean not null default true,
  archived_at      timestamptz,
  archived_by      uuid references auth.users(id),
  archived_reason  text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  updated_by       uuid references auth.users(id)
);

comment on table public.plan_catalog is
  'Catálogo de planes/precios editables desde el panel admin.';

create index if not exists plan_catalog_active_idx
  on public.plan_catalog (display_order, code)
  where is_active = true and archived_at is null;

alter table public.plan_catalog enable row level security;

drop policy if exists "plan_catalog read all" on public.plan_catalog;
create policy "plan_catalog read all"
on public.plan_catalog
for select
to authenticated
using (true);  -- los planes son públicos (precios visibles a clientes en signup)

-- Mutaciones solo vía RPCs security definer.


-- Seed con los precios actuales (idempotente).
insert into public.plan_catalog (code, name, description, price_monthly, display_order)
values
  ('trial', 'Trial',  'Prueba gratuita por tiempo limitado.',    0,    0),
  ('free',  'Free',   'Plan gratuito permanente con límites.',   0,    1),
  ('basic', 'Básico', 'Para comercios pequeños.',              990,    2),
  ('pro',   'Pro',    'Para comercios con operación completa.', 2490,  3)
on conflict (code) do nothing;


-- Reemplazar check constraints por FK ----------------------------------------
-- memberships.plan_type
alter table public.memberships
  drop constraint if exists memberships_plan_type_check;

alter table public.memberships
  drop constraint if exists memberships_plan_type_fkey;

alter table public.memberships
  add constraint memberships_plan_type_fkey
  foreign key (plan_type) references public.plan_catalog(code)
  on update cascade
  on delete restrict;

-- membership_invoices.plan_type
alter table public.membership_invoices
  drop constraint if exists membership_invoices_plan_type_check;

alter table public.membership_invoices
  drop constraint if exists membership_invoices_plan_type_fkey;

alter table public.membership_invoices
  add constraint membership_invoices_plan_type_fkey
  foreign key (plan_type) references public.plan_catalog(code)
  on update cascade
  on delete restrict;


-- Reescribir plan_monthly_fee para leer de la tabla --------------------------
create or replace function public.plan_monthly_fee(p_plan text)
returns numeric
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select price_monthly from public.plan_catalog where code = p_plan limit 1),
    0::numeric
  );
$$;

comment on function public.plan_monthly_fee(text) is
  'Tarifa mensual del plan leída de plan_catalog. Devuelve 0 si el plan no existe.';


-- ---------------------------------------------------------------------------
-- RPC: get_plans()
-- ---------------------------------------------------------------------------
create or replace function public.get_plans()
returns table (
  code           text,
  name           text,
  description    text,
  price_monthly  numeric,
  currency_code  text,
  features       jsonb,
  display_order  int,
  is_active      boolean,
  archived_at    timestamptz,
  archived_reason text,
  active_subscribers int,
  created_at     timestamptz,
  updated_at     timestamptz
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

grant execute on function public.get_plans() to authenticated;


-- ---------------------------------------------------------------------------
-- RPC: upsert_plan
--   Crea o actualiza. `p_code` es la PK (no se cambia).
-- ---------------------------------------------------------------------------
create or replace function public.upsert_plan(
  p_code          text,
  p_name          text,
  p_description   text,
  p_price_monthly numeric,
  p_features      jsonb,
  p_display_order int,
  p_is_active     boolean default true
)
returns public.plan_catalog
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_plan public.plan_catalog;
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
    features, display_order, is_active,
    updated_at, updated_by
  )
  values (
    v_code, v_name, nullif(trim(coalesce(p_description, '')), ''),
    p_price_monthly,
    coalesce(p_features, '[]'::jsonb),
    coalesce(p_display_order, 0),
    coalesce(p_is_active, true),
    now(), auth.uid()
  )
  on conflict (code) do update
    set name           = excluded.name,
        description    = excluded.description,
        price_monthly  = excluded.price_monthly,
        features       = excluded.features,
        display_order  = excluded.display_order,
        is_active      = excluded.is_active,
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

grant execute on function public.upsert_plan(text, text, text, numeric, jsonb, int, boolean)
  to authenticated;


-- ---------------------------------------------------------------------------
-- RPC: archive_plan(code, reason)
--   Soft delete. Bloquea si hay suscriptores ACTIVOS al plan.
-- ---------------------------------------------------------------------------
create or replace function public.archive_plan(
  p_code   text,
  p_reason text
)
returns public.plan_catalog
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_plan        public.plan_catalog;
  v_subscribers int;
  v_reason      text := trim(coalesce(p_reason, ''));
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if v_reason = '' then
    raise exception 'La razón es obligatoria.' using errcode = '22023';
  end if;

  select * into v_plan from public.plan_catalog where code = p_code;
  if v_plan.code is null then
    raise exception 'Plan % no existe.', p_code using errcode = 'P0002';
  end if;
  if v_plan.archived_at is not null then
    raise exception 'Plan % ya está archivado.', p_code using errcode = '22023';
  end if;

  select count(*) into v_subscribers
    from public.memberships
   where plan_type = p_code
     and status    = 'active';

  if v_subscribers > 0 then
    raise exception
      'No se puede archivar el plan %: tiene % suscriptor(es) activo(s). Migra los suscriptores primero.',
      p_code, v_subscribers
      using errcode = '23503';
  end if;

  update public.plan_catalog
     set archived_at     = now(),
         archived_by     = auth.uid(),
         archived_reason = v_reason,
         is_active       = false,
         updated_at      = now(),
         updated_by      = auth.uid()
   where code = p_code
  returning * into v_plan;

  insert into public.noc_audit_log (
    user_id, action, target_resource, payload
  )
  values (
    auth.uid(),
    'plan.archive',
    'plan_catalog',
    jsonb_build_object('code', p_code, 'reason', v_reason)
  );

  return v_plan;
end;
$$;

grant execute on function public.archive_plan(text, text) to authenticated;


-- ---------------------------------------------------------------------------
-- RPC: restore_plan(code)
-- ---------------------------------------------------------------------------
create or replace function public.restore_plan(p_code text)
returns public.plan_catalog
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_plan public.plan_catalog;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  update public.plan_catalog
     set archived_at     = null,
         archived_by     = null,
         archived_reason = null,
         is_active       = true,
         updated_at      = now(),
         updated_by      = auth.uid()
   where code = p_code
     and archived_at is not null
  returning * into v_plan;

  if v_plan.code is null then
    raise exception 'Plan % no está archivado o no existe.', p_code
      using errcode = 'P0002';
  end if;

  insert into public.noc_audit_log (
    user_id, action, target_resource, payload
  )
  values (
    auth.uid(),
    'plan.restore',
    'plan_catalog',
    jsonb_build_object('code', p_code)
  );

  return v_plan;
end;
$$;

grant execute on function public.restore_plan(text) to authenticated;

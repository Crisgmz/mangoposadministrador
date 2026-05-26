-- ---------------------------------------------------------------------------
-- 0028_plan_catalog_fix.sql
--
-- Repara el estado dejado por 0025 y 0027. La 0025 hizo rollback al
-- aplicar `ALTER TABLE memberships ADD CONSTRAINT ... FOREIGN KEY ...
-- REFERENCES plan_catalog(code)` — probablemente hay valores de
-- `memberships.plan_type` que no están en el seed (nulls, vacíos, planes
-- legacy). Como toda la migración se hizo rollback, `plan_catalog` no se
-- creó y 0027 luego falló con "type plan_catalog does not exist".
--
-- Esta migración es **idempotente** y **no agrega FK estricta** a
-- memberships / membership_invoices. El catálogo es referencial: la app
-- valida en RPCs, no requiere FK rígido en Postgres. Esto evita romper
-- por data legacy.
--
-- Pasos:
--   1) Drop seguro de constraints de FK que la 0025 hubiera dejado.
--   2) Drop opcional de los CHECK viejos (no es crítico; se reinstala
--      uno más permisivo o se omite).
--   3) Crear `plan_catalog` si no existe.
--   4) Seed con los planes conocidos (trial/free/basic/pro).
--   5) Sembrar **automáticamente** cualquier plan_type usado en memberships
--      que falte en plan_catalog (con price=0, nombre=code, archivado),
--      para no perder visibilidad de planes legacy.
--   6) Reescribir `plan_monthly_fee(text)` para leer de tabla.
--   7) Recrear los 4 RPCs `admin_*`.
-- ---------------------------------------------------------------------------

-- 1) Limpiar FK que la 0025 hubiera dejado a medias.
alter table public.memberships
  drop constraint if exists memberships_plan_type_fkey;

alter table public.membership_invoices
  drop constraint if exists membership_invoices_plan_type_fkey;


-- 2) Drop también los CHECK viejos, por si la 0025 alcanzó a tirarlos
--    o si quedaron. Después de esto `plan_type` queda como text libre,
--    validado solo por la app.
alter table public.memberships
  drop constraint if exists memberships_plan_type_check;

alter table public.membership_invoices
  drop constraint if exists membership_invoices_plan_type_check;


-- 3) Crear catálogo.
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

create index if not exists plan_catalog_active_idx
  on public.plan_catalog (display_order, code)
  where is_active = true and archived_at is null;

alter table public.plan_catalog enable row level security;

drop policy if exists "plan_catalog read all" on public.plan_catalog;
create policy "plan_catalog read all"
on public.plan_catalog
for select
to authenticated
using (true);


-- 4) Seed estándar.
insert into public.plan_catalog (code, name, description, price_monthly, display_order)
values
  ('trial', 'Trial',  'Prueba gratuita por tiempo limitado.',    0,    0),
  ('free',  'Free',   'Plan gratuito permanente con límites.',   0,    1),
  ('basic', 'Básico', 'Para comercios pequeños.',              990,    2),
  ('pro',   'Pro',    'Para comercios con operación completa.', 2490,  3)
on conflict (code) do nothing;


-- 5) Sembrar planes legacy detectados en memberships que no estén en el
--    catálogo. Se marcan como archivados para que la UI los muestre como
--    "legacy" pero permita ver/migrar a los clientes que los usan.
insert into public.plan_catalog (
  code, name, description, price_monthly,
  display_order, is_active, archived_at, archived_reason
)
select distinct
  lower(trim(m.plan_type))                            as code,
  initcap(replace(lower(trim(m.plan_type)), '_', ' ')) as name,
  'Plan legacy detectado en migración 0028.'         as description,
  0                                                   as price_monthly,
  100                                                 as display_order,
  false                                               as is_active,
  now()                                               as archived_at,
  'Plan legacy: detectado en memberships pero no en catálogo nuevo.' as archived_reason
from public.memberships m
where m.plan_type is not null
  and trim(m.plan_type) <> ''
  and lower(trim(m.plan_type)) not in (
    select code from public.plan_catalog
  )
on conflict (code) do nothing;


-- 6) plan_monthly_fee lee de tabla.
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


-- 7) RPCs admin_*. Drop previo por si hay versiones huérfanas, luego recrear.
drop function if exists public.admin_get_plans();
drop function if exists public.admin_upsert_plan(text, text, text, numeric, jsonb, int, boolean);
drop function if exists public.admin_archive_plan(text, text);
drop function if exists public.admin_restore_plan(text);

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


create or replace function public.admin_upsert_plan(
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

grant execute on function public.admin_upsert_plan(text, text, text, numeric, jsonb, int, boolean)
  to authenticated;


create or replace function public.admin_archive_plan(
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

grant execute on function public.admin_archive_plan(text, text) to authenticated;


create or replace function public.admin_restore_plan(p_code text)
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

grant execute on function public.admin_restore_plan(text) to authenticated;


-- Refrescar el cache de PostgREST.
notify pgrst, 'reload schema';

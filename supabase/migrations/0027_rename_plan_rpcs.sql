-- ---------------------------------------------------------------------------
-- 0027_rename_plan_rpcs.sql
--
-- `public.get_plans()` colisionó con una función homónima del schema de
-- `mangospos` (con otra signature), causando que PostgREST no resuelva
-- la versión sin parámetros del admin. Solución: prefijar todas las RPCs
-- de planes con `admin_` para garantizar que el namespace del admin no
-- choque con el del proyecto principal.
--
-- Drop las versiones de 0025 y recrearlas con nombres `admin_*`.
-- ---------------------------------------------------------------------------

drop function if exists public.get_plans();
drop function if exists public.upsert_plan(text, text, text, numeric, jsonb, int, boolean);
drop function if exists public.archive_plan(text, text);
drop function if exists public.restore_plan(text);


-- ---------------------------------------------------------------------------
-- admin_get_plans()
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_plans()
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

grant execute on function public.admin_get_plans() to authenticated;


-- ---------------------------------------------------------------------------
-- admin_upsert_plan(code, name, description, price, features, display_order, is_active)
-- ---------------------------------------------------------------------------
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

grant execute on function public.admin_upsert_plan(text, text, text, numeric, jsonb, int, boolean)
  to authenticated;


-- ---------------------------------------------------------------------------
-- admin_archive_plan(code, reason)
-- ---------------------------------------------------------------------------
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


-- ---------------------------------------------------------------------------
-- admin_restore_plan(code)
-- ---------------------------------------------------------------------------
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

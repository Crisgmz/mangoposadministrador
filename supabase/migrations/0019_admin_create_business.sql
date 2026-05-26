-- ---------------------------------------------------------------------------
-- 0019_admin_create_business.sql
--
-- Onboarding manual de negocios desde el panel administrador.
--
-- RPC `admin_create_business`:
--   1) Toma `p_owner_email` y busca el usuario en `auth.users`. Si no existe,
--      falla con instrucción clara (el owner debe registrarse primero en
--      mangopos.do/signup — la creación de users vía SQL no es soportada por
--      Supabase sin service_role; se añadirá Edge Function aparte si se
--      requiere onboarding "full sales-assisted" sin participación del cliente).
--   2) Crea `businesses` con los datos provistos.
--   3) Crea `memberships` (plan + trial_days → end_date) atada al owner con
--      role='owner'.
--   4) Registra en `noc_audit_log`.
--
-- Devuelve el id del negocio creado. La UI puede navegar a /businesses/<id>.
-- ---------------------------------------------------------------------------

create or replace function public.admin_create_business(
  p_owner_email   text,
  p_business_name text,
  p_business_type text default null,
  p_domain        text default null,
  p_environment   text default 'sandbox',
  p_plan_type     text default 'trial',
  p_trial_days    int  default 30
)
returns table (
  business_id uuid,
  owner_id    uuid,
  membership_id uuid
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_owner_id      uuid;
  v_business_id   uuid;
  v_membership_id uuid;
  v_owner_email   text := lower(trim(coalesce(p_owner_email, '')));
  v_business_name text := trim(coalesce(p_business_name, ''));
  v_domain        text := lower(trim(coalesce(p_domain, '')));
  v_environment   text := coalesce(p_environment, 'sandbox');
  v_plan_type     text := coalesce(p_plan_type, 'trial');
  v_trial_days    int  := greatest(coalesce(p_trial_days, 30), 0);
  v_end_date      timestamptz;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Validaciones de input.
  if v_owner_email = '' then
    raise exception 'El email del owner es obligatorio.' using errcode = '22023';
  end if;
  if v_business_name = '' then
    raise exception 'El nombre del negocio es obligatorio.' using errcode = '22023';
  end if;
  if v_plan_type not in ('trial', 'free', 'basic', 'pro') then
    raise exception 'Plan inválido: %', v_plan_type using errcode = '22023';
  end if;
  if v_environment not in ('production', 'sandbox') then
    raise exception 'Entorno inválido: %', v_environment using errcode = '22023';
  end if;

  -- Buscar el owner. Debe existir antes (registro público).
  select u.id into v_owner_id
    from auth.users u
   where lower(u.email) = v_owner_email
   limit 1;

  if v_owner_id is null then
    raise exception
      'No existe un usuario con email %. El owner debe registrarse primero (mangopos.do/signup) y luego completar el onboarding desde el panel.',
      v_owner_email
      using errcode = 'P0002';
  end if;

  -- Verificar dominio único si se proveyó.
  if v_domain <> '' then
    if exists (select 1 from public.businesses where lower(domain) = v_domain) then
      raise exception 'El dominio % ya está en uso.', v_domain
        using errcode = '23505';
    end if;
  end if;

  v_end_date := now() + make_interval(days => v_trial_days);

  -- Crear el negocio.
  insert into public.businesses (
    business_name,
    business_type,
    status,
    domain,
    environment,
    owner_id
  )
  values (
    v_business_name,
    nullif(trim(coalesce(p_business_type, '')), ''),
    'active',
    nullif(v_domain, ''),
    v_environment,
    v_owner_id
  )
  returning id into v_business_id;

  -- Crear la membresía atada al owner.
  insert into public.memberships (
    user_id,
    business_id,
    plan_type,
    status,
    start_date,
    end_date,
    role
  )
  values (
    v_owner_id,
    v_business_id,
    v_plan_type,
    'active',
    now(),
    v_end_date,
    'owner'::public.member_role
  )
  returning id into v_membership_id;

  -- Auditoría.
  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'business.create',
    'businesses',
    v_business_id,
    v_business_id,
    jsonb_build_object(
      'owner_email',   v_owner_email,
      'owner_id',      v_owner_id,
      'business_name', v_business_name,
      'plan_type',     v_plan_type,
      'environment',   v_environment,
      'trial_days',    v_trial_days,
      'end_date',      v_end_date
    )
  );

  business_id   := v_business_id;
  owner_id      := v_owner_id;
  membership_id := v_membership_id;
  return next;
end;
$$;

comment on function public.admin_create_business(text, text, text, text, text, text, int) is
  'Onboarding manual de negocios. El owner debe existir en auth.users. Crea businesses + memberships y audita.';

grant execute on function public.admin_create_business(text, text, text, text, text, text, int) to authenticated;

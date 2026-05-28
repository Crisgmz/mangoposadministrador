-- ---------------------------------------------------------------------------
-- 0036_business_team.sql
--
-- RPC para que el administrador vea la información de los clientes:
-- owner del negocio + miembros (memberships) con sus datos de contacto
-- (email, nombre, teléfono) desde auth.users + profiles.
--
-- El campo `is_owner` se calcula comparando `memberships.user_id` con
-- `businesses.owner_id`. El owner siempre aparece primero, después los
-- demás miembros ordenados por fecha de alta (más antiguos primero).
--
-- Solo `is_platform_operator()` puede ejecutar esto — son datos personales
-- de los usuarios finales de los comercios.
-- ---------------------------------------------------------------------------

create or replace function public.admin_get_business_team(p_business_id uuid)
returns table (
  user_id            uuid,
  membership_id      uuid,
  is_owner           boolean,
  role               text,
  status             text,
  email              text,
  email_confirmed_at timestamptz,
  full_name          text,
  phone              text,
  last_sign_in_at    timestamptz,
  user_created_at    timestamptz,
  membership_created_at timestamptz,
  plan_type          text,
  end_date           timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select owner_id into v_owner_id
    from public.businesses
   where id = p_business_id;

  if v_owner_id is null and not exists (
    select 1 from public.businesses where id = p_business_id
  ) then
    raise exception 'Negocio % no existe', p_business_id
      using errcode = 'P0002';
  end if;

  return query
  select
    m.user_id,
    m.id                                                       as membership_id,
    (m.user_id = v_owner_id)                                   as is_owner,
    coalesce(m.role::text, 'member')                           as role,
    coalesce(m.status, 'active')                               as status,
    u.email,
    u.email_confirmed_at,
    coalesce(
      p.full_name,
      nullif(trim(coalesce(u.raw_user_meta_data->>'full_name', '')), ''),
      nullif(trim(coalesce(u.raw_user_meta_data->>'name', '')), '')
    )                                                          as full_name,
    coalesce(
      nullif(trim(coalesce(p.phone, '')), ''),
      u.phone
    )                                                          as phone,
    u.last_sign_in_at,
    u.created_at                                               as user_created_at,
    m.created_at                                               as membership_created_at,
    m.plan_type,
    m.end_date
  from public.memberships m
  join auth.users     u on u.id = m.user_id
  left join public.profiles p on p.id = m.user_id
  where m.business_id = p_business_id
  -- Owner primero (descending por is_owner), luego más antiguos primero.
  order by (m.user_id = v_owner_id) desc nulls last,
           m.created_at asc;
end;
$$;

comment on function public.admin_get_business_team(uuid) is
  'Devuelve owner + miembros de un negocio con email, nombre y teléfono. Solo operadores.';

grant execute on function public.admin_get_business_team(uuid) to authenticated;

notify pgrst, 'reload schema';

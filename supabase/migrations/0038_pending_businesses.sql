-- ---------------------------------------------------------------------------
-- 0038_pending_businesses.sql
--
-- Cola de cuentas pendientes (PRD `docs/PRD_ADMIN_CUENTAS_PENDIENTES.md`).
-- Implementa los 4 RPCs que la pantalla "Cuentas pendientes" necesita:
--
--   * admin_list_pending_businesses(search, limit, offset, only_with_card)
--   * admin_pending_count()
--   * admin_approve_pending_business(business_id, reason?)
--   * admin_reject_pending_business(business_id, reason)
--
-- Audita en `noc_audit_log` con actions:
--   * `business.approve` (pending → active)
--   * `business.reject`  (pending → inactive, con razón obligatoria)
--
-- No crea tabla `business_status_audit` separada — el PRD la propone como
-- opción, pero `noc_audit_log` ya cubre el caso (mismo audit que el resto
-- de acciones admin). Si en el futuro hace falta separar, se agrega.
--
-- Notas de joins:
--   * `businesses.business_name`, `branch_name`, `business_type`, `country`,
--     `address`, `phone`, `domain`, `status`, `created_at`, `owner_id` —
--     tabla del repo principal `mangospos`; este admin solo lee.
--   * `auth.users.email`, `email_confirmed_at`, `last_sign_in_at`,
--     `raw_user_meta_data` — managed by Supabase Auth.
--   * `public.profiles.full_name` — fallback a meta de auth si null.
--   * `public.memberships` filtrado por `is_billing_anchor = true` para la
--     membership "raíz" del business.
--   * `public.plan_catalog` (de la migración 0028) — join via `plan_type`
--     text que ahora referencia code del catálogo.
--   * `public.payment_methods` — del repo de POS. Si la tabla no existiera
--     en este schema, el RPC falla al ejecutarse; en ese caso editar para
--     omitir el `has_verified_card`.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- admin_pending_count()
-- ---------------------------------------------------------------------------
create or replace function public.admin_pending_count()
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select count(*)::int into v_count
    from public.businesses
   where status = 'pending';

  return coalesce(v_count, 0);
end;
$$;

grant execute on function public.admin_pending_count() to authenticated;


-- ---------------------------------------------------------------------------
-- admin_list_pending_businesses(search?, limit?, offset?, only_with_card?)
--
-- Devuelve todas las cuentas con status='pending' con joins a owner, plan
-- y método de pago. Filtros opcionales:
--   * search: nombre del negocio (ILIKE), email del owner (ILIKE) o
--             match exacto del UUID.
--   * only_with_card: solo cuentas con payment_methods.status='verified'.
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_pending_businesses(
  p_search         text    default null,
  p_limit          int     default 50,
  p_offset         int     default 0,
  p_only_with_card boolean default false
)
returns table (
  business_id              uuid,
  business_name            text,
  branch_name              text,
  business_type            text,
  country                  text,
  address                  text,
  phone                    text,
  domain                   text,
  status                   text,
  created_at               timestamptz,
  owner_id                 uuid,
  owner_email              text,
  owner_full_name          text,
  email_confirmed_at       timestamptz,
  last_sign_in_at          timestamptz,
  plan_code                text,
  plan_name                text,
  plan_monthly_price       numeric,
  membership_billing_status text,
  trial_ends_at            timestamptz,
  next_billing_date        date,
  has_verified_card        boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_search text := lower(trim(coalesce(p_search, '')));
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return query
  select
    b.id,
    b.business_name,
    b.branch_name,
    b.business_type,
    b.country,
    b.address,
    b.phone,
    b.domain,
    b.status,
    b.created_at,
    b.owner_id,
    u.email                                                        as owner_email,
    coalesce(
      p.full_name,
      nullif(trim(coalesce(u.raw_user_meta_data->>'full_name', '')), ''),
      nullif(trim(coalesce(u.raw_user_meta_data->>'name', '')), '')
    )                                                              as owner_full_name,
    u.email_confirmed_at,
    u.last_sign_in_at,
    m.plan_type                                                    as plan_code,
    pc.name                                                        as plan_name,
    pc.price_monthly                                               as plan_monthly_price,
    m.billing_status                                               as membership_billing_status,
    m.trial_ends_at,
    m.next_billing_date,
    exists (
      select 1 from public.payment_methods pm
       where pm.business_id = b.id
         and pm.status      = 'verified'
    )                                                              as has_verified_card
  from public.businesses b
  left join auth.users     u  on u.id = b.owner_id
  left join public.profiles p on p.id = b.owner_id
  left join public.memberships m
    on m.business_id = b.id
   and m.is_billing_anchor = true
  left join public.plan_catalog pc on pc.code = m.plan_type
  where b.status = 'pending'
    and (
      v_search = ''
      or lower(b.business_name) like '%' || v_search || '%'
      or lower(coalesce(u.email, '')) like '%' || v_search || '%'
      or b.id::text = v_search
    )
    and (
      not p_only_with_card
      or exists (
        select 1 from public.payment_methods pm
         where pm.business_id = b.id
           and pm.status      = 'verified'
      )
    )
  order by b.created_at desc
  limit greatest(p_limit, 1)
  offset greatest(p_offset, 0);
end;
$$;

grant execute on function public.admin_list_pending_businesses(text, int, int, boolean)
  to authenticated;


-- ---------------------------------------------------------------------------
-- admin_approve_pending_business(business_id, reason?)
--
-- Activa una cuenta que está en `pending`. Solo aplica si la cuenta sigue
-- en pending (idempotencia: si ya está active, falla con mensaje claro).
-- ---------------------------------------------------------------------------
create or replace function public.admin_approve_pending_business(
  p_business_id uuid,
  p_reason      text default null
)
returns public.businesses
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_before public.businesses;
  v_after  public.businesses;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select * into v_before from public.businesses where id = p_business_id;
  if v_before.id is null then
    raise exception 'Negocio % no existe', p_business_id
      using errcode = 'P0002';
  end if;

  if v_before.status <> 'pending' then
    raise exception 'La cuenta no está pendiente (status actual: %).',
      v_before.status using errcode = '22023';
  end if;

  update public.businesses
     set status     = 'active',
         updated_at = now()
   where id = p_business_id
  returning * into v_after;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'business.approve',
    'businesses',
    p_business_id,
    p_business_id,
    jsonb_build_object(
      'reason',          nullif(trim(coalesce(p_reason, '')), ''),
      'previous_status', v_before.status,
      'business_name',   v_before.business_name
    )
  );

  return v_after;
end;
$$;

comment on function public.admin_approve_pending_business(uuid, text) is
  'Aprueba una cuenta pending → active. Auditado como business.approve.';

grant execute on function public.admin_approve_pending_business(uuid, text)
  to authenticated;


-- ---------------------------------------------------------------------------
-- admin_reject_pending_business(business_id, reason)
--
-- Rechaza una cuenta pending → inactive. Razón obligatoria.
-- ---------------------------------------------------------------------------
create or replace function public.admin_reject_pending_business(
  p_business_id uuid,
  p_reason      text
)
returns public.businesses
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_before public.businesses;
  v_after  public.businesses;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if length(v_reason) < 10 then
    raise exception 'La razón es obligatoria (mínimo 10 caracteres).'
      using errcode = '22023';
  end if;

  select * into v_before from public.businesses where id = p_business_id;
  if v_before.id is null then
    raise exception 'Negocio % no existe', p_business_id
      using errcode = 'P0002';
  end if;

  if v_before.status <> 'pending' then
    raise exception 'La cuenta no está pendiente (status actual: %).',
      v_before.status using errcode = '22023';
  end if;

  update public.businesses
     set status     = 'inactive',
         updated_at = now()
   where id = p_business_id
  returning * into v_after;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'business.reject',
    'businesses',
    p_business_id,
    p_business_id,
    jsonb_build_object(
      'reason',          v_reason,
      'previous_status', v_before.status,
      'business_name',   v_before.business_name
    )
  );

  return v_after;
end;
$$;

comment on function public.admin_reject_pending_business(uuid, text) is
  'Rechaza una cuenta pending → inactive. Razón obligatoria. Audita.';

grant execute on function public.admin_reject_pending_business(uuid, text)
  to authenticated;


notify pgrst, 'reload schema';

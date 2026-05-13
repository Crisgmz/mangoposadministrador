-- ============================================================================
-- Migración 0007 — Edición de membresía desde la consola operadora
--
-- RPC `update_business_membership` que permite al operador, por cada negocio:
--   - Cambiar el plan actual (trial / free / basic / pro)
--   - Establecer la fecha de corte (`end_date`)
--   - Marcar la membresía como `active` (pagada), `expired` (vencida)
--     o `canceled`.
--
-- Si el negocio aún no tiene una membresía, se crea una nueva atada al
-- `owner_id` del negocio (rol `owner`). Si ya tiene, se actualiza la más
-- reciente. Idempotente.
-- ============================================================================

create or replace function public.update_business_membership(
  p_business_id uuid,
  p_plan_type   text,
  p_end_date    timestamptz,
  p_status      text
) returns public.memberships
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_membership public.memberships;
  v_owner_id   uuid;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_plan_type not in ('trial', 'free', 'basic', 'pro') then
    raise exception 'Plan inválido: %', p_plan_type using errcode = '22023';
  end if;

  if p_status not in ('active', 'canceled', 'expired') then
    raise exception 'Estado inválido: %', p_status using errcode = '22023';
  end if;

  -- Membresía más reciente del negocio (cualquier estado).
  select * into v_membership
    from public.memberships
   where business_id = p_business_id
   order by created_at desc
   limit 1;

  if v_membership.id is null then
    -- No existe, creamos una nueva atada al owner del negocio.
    select owner_id into v_owner_id
      from public.businesses
     where id = p_business_id;

    if v_owner_id is null then
      raise exception 'Negocio % no existe', p_business_id;
    end if;

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
      p_business_id,
      p_plan_type,
      p_status,
      now(),
      p_end_date,
      'owner'::public.member_role
    )
    returning * into v_membership;
  else
    update public.memberships
       set plan_type = p_plan_type,
           status    = p_status,
           end_date  = p_end_date
     where id = v_membership.id
    returning * into v_membership;
  end if;

  return v_membership;
end;
$$;

comment on function public.update_business_membership(uuid, text, timestamptz, text) is
  'Actualiza (o crea) la membresía de un negocio: plan, fecha de corte y estado. Solo operadores.';

grant execute on function public.update_business_membership(uuid, text, timestamptz, text) to authenticated;

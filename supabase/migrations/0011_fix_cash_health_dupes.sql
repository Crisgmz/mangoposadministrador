-- ============================================================================
-- Migración 0011 — Fix duplicados en v_admin_cash_health
--
-- La versión original hacía `left join public.employees e on e.user_id = h.user_id`
-- sin acotar por negocio. Si el mismo `user_id` aparece como empleado en N
-- negocios, el join produce N filas por sesión → la sección de Cajas mostraba
-- "el negocio con la caja duplicada".
--
-- Solución: scopear el JOIN con `business_id` para que solo traiga el
-- registro de empleado del negocio al que pertenece la sesión.
-- ============================================================================

drop view if exists public.v_admin_cash_health cascade;

create view public.v_admin_cash_health as
select
  h.session_id,
  h.business_id,
  b.business_name,
  b.environment,
  h.cash_register_id,
  h.caja_nombre,
  h.user_id,
  coalesce(
    nullif(trim(coalesce(e.first_name, '') || ' ' || coalesce(e.last_name, '')), ''),
    p.full_name
  )                                                  as cashier_name,
  h.opened_at,
  h.closed_at,
  h.status,
  h.duracion,
  extract(epoch from h.duracion)::bigint             as duracion_seconds,
  h.start_amount,
  h.ventas_efectivo,
  h.depositos,
  h.retiros,
  h.gastos,
  h.saldo_esperado_actual,
  s.end_amount,
  s.difference,
  s.variance_flagged,
  s.notes,
  h.needs_attention
from public.v_cash_sessions_health h
join public.cash_register_sessions s on s.id = h.session_id
join public.businesses             b on b.id = h.business_id
-- Importante: acotar `employees` al business_id, sino multiplicamos filas
-- cuando el mismo user es empleado de varios negocios.
left join public.employees         e
  on e.user_id = h.user_id and e.business_id = h.business_id
left join public.profiles          p on p.id = h.user_id;

comment on view public.v_admin_cash_health is
  'Salud de cajas cross-tenant. Extiende v_cash_sessions_health con '
  'business_name, environment y nombre del cajero. El JOIN a employees '
  'está acotado por business_id para evitar duplicados cuando un user '
  'es empleado en varios negocios.';

-- Recrear las RPCs que dependen de la vista — `drop view ... cascade`
-- las eliminó.
create or replace function public.get_admin_cash_health(
  p_business_id uuid default null,
  p_filter      text default 'all'
)
returns setof public.v_admin_cash_health
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
  select * from public.v_admin_cash_health h
   where (p_business_id is null or h.business_id = p_business_id)
     and case p_filter
           when 'open'             then h.status = 'open'
           when 'needs_attention'  then h.needs_attention = true
           when 'closed_today'     then h.status = 'closed'
                                    and h.closed_at >= now() - interval '24 hours'
           when 'variance_flagged' then h.variance_flagged = true
           else true
         end
   order by
     case when h.status = 'open' then 0 else 1 end,
     h.needs_attention desc nulls last,
     h.variance_flagged desc nulls last,
     h.opened_at desc;
end;
$$;

grant execute on function public.get_admin_cash_health(uuid, text) to authenticated;

create or replace function public.get_cash_session_detail(p_session_id uuid)
returns public.v_admin_cash_health
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_row public.v_admin_cash_health;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  select * into v_row
    from public.v_admin_cash_health
   where session_id = p_session_id
   limit 1;

  return v_row;
end;
$$;

grant execute on function public.get_cash_session_detail(uuid) to authenticated;

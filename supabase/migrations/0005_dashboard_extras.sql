-- ============================================================================
-- Migración 0005 — RPCs extras de la consola operadora
--
--   1) `get_critical_audit_logs`     — auditoría plataforma (filtrable por negocio)
--   2) `get_recent_print_failures`   — fallas de impresión (filtrable por negocio)
--   3) `get_business_week_trend`     — ingresos esta semana vs anterior, por negocio
--   4) `toggle_business_status`      — activar/desactivar un negocio
--
-- Todas con guard `is_platform_operator()`. Idempotentes.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) get_critical_audit_logs(p_business_id, p_limit)
--    Acciones consideradas críticas/operativas (anulaciones, eliminaciones,
--    cancelaciones). Si `p_business_id` es null, devuelve plataforma completa.
-- ---------------------------------------------------------------------------
create or replace function public.get_critical_audit_logs(
  p_business_id uuid default null,
  p_limit       int  default 100
)
returns table (
  id            uuid,
  business_id   uuid,
  business_name text,
  user_id       uuid,
  user_name     text,
  action        text,
  reason        text,
  ref_table     text,
  ref_id        uuid,
  severity      text,
  created_at    timestamptz
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
  select al.id,
         al.business_id,
         b.business_name,
         al.employee_id                                              as user_id,
         nullif(trim(coalesce(e.first_name, '') || ' ' ||
                     coalesce(e.last_name, '')), '')                 as user_name,
         al.action,
         al.reason,
         al.ref_type                                                 as ref_table,
         al.ref_id,
         case
           when al.action ilike 'void%' or al.action ilike '%delete%' then 'critical'
           when al.action ilike 'cancel%'                              then 'warning'
           else 'info'
         end                                                         as severity,
         al.created_at
    from public.audit_logs al
    join public.businesses b on b.id = al.business_id
    left join public.employees e on e.id = al.employee_id
   where (p_business_id is null or al.business_id = p_business_id)
     and (
           al.action ilike 'void%'
        or al.action ilike '%delete%'
        or al.action ilike 'cancel%'
        or al.action ilike '%refund%'
     )
   order by al.created_at desc
   limit greatest(p_limit, 1);
end;
$$;

comment on function public.get_critical_audit_logs(uuid, int) is
  'Auditoría: acciones críticas (anulaciones, eliminaciones, cancelaciones, refunds).';

grant execute on function public.get_critical_audit_logs(uuid, int) to authenticated;


-- ---------------------------------------------------------------------------
-- 2) get_recent_print_failures(p_business_id, p_hours, p_limit)
-- ---------------------------------------------------------------------------
create or replace function public.get_recent_print_failures(
  p_business_id uuid default null,
  p_hours       int  default 24,
  p_limit       int  default 100
)
returns table (
  id            uuid,
  business_id   uuid,
  business_name text,
  printer_ip    text,
  printer_port  int,
  printer_name  text,
  status        text,
  error         text,
  created_at    timestamptz
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
  select pj.id,
         pj.business_id,
         b.business_name,
         pj.ip                                               as printer_ip,
         pj.port                                             as printer_port,
         coalesce(pr.name, '—')                              as printer_name,
         pj.status,
         pj.error,
         pj.created_at
    from public.print_jobs pj
    join public.businesses b  on b.id = pj.business_id
    left join public.printers pr
           on pr.business_id = pj.business_id
          and (pr.ip_address = pj.ip or pr.ip::text = pj.ip)
   where pj.status = 'failed'
     and pj.created_at >= now() - make_interval(hours => greatest(p_hours, 1))
     and (p_business_id is null or pj.business_id = p_business_id)
   order by pj.created_at desc
   limit greatest(p_limit, 1);
end;
$$;

comment on function public.get_recent_print_failures(uuid, int, int) is
  'Fallas de impresión recientes (default últimas 24h).';

grant execute on function public.get_recent_print_failures(uuid, int, int) to authenticated;


-- ---------------------------------------------------------------------------
-- 3) get_business_week_trend()
--    Ingresos plataforma semana actual vs semana anterior, por negocio.
-- ---------------------------------------------------------------------------
create or replace function public.get_business_week_trend()
returns table (
  business_id        uuid,
  business_name      text,
  week_revenue       numeric,
  last_week_revenue  numeric,
  trend_pct          numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_now            timestamptz := now();
  v_week_start     timestamptz := v_now - interval '7 days';
  v_lastweek_start timestamptz := v_now - interval '14 days';
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return query
  with this_week as (
    select business_id, sum(amount)::numeric as revenue
      from public.payments
     where status = 'completed' and created_at >= v_week_start
     group by business_id
  ),
  last_week as (
    select business_id, sum(amount)::numeric as revenue
      from public.payments
     where status = 'completed'
       and created_at >= v_lastweek_start
       and created_at <  v_week_start
     group by business_id
  )
  select b.id as business_id,
         b.business_name,
         coalesce(tw.revenue, 0)::numeric as week_revenue,
         coalesce(lw.revenue, 0)::numeric as last_week_revenue,
         case
           when coalesce(lw.revenue, 0) = 0 then 0::numeric
           else round(((coalesce(tw.revenue, 0) - lw.revenue) / lw.revenue) * 100, 1)
         end as trend_pct
    from public.businesses b
    left join this_week tw on tw.business_id = b.id
    left join last_week lw on lw.business_id = b.id
   order by b.business_name;
end;
$$;

comment on function public.get_business_week_trend() is
  'Ingresos semana actual vs semana anterior por negocio (con % de cambio).';

grant execute on function public.get_business_week_trend() to authenticated;


-- ---------------------------------------------------------------------------
-- 4) toggle_business_status(p_business_id)
--    Alterna `businesses.status` entre 'active' e 'inactive'. Devuelve la fila.
-- ---------------------------------------------------------------------------
create or replace function public.toggle_business_status(p_business_id uuid)
returns public.businesses
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_business public.businesses;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  update public.businesses
     set status = case when status = 'active' then 'inactive' else 'active' end,
         updated_at = now()
   where id = p_business_id
  returning * into v_business;

  if v_business.id is null then
    raise exception 'Negocio % no existe', p_business_id;
  end if;

  return v_business;
end;
$$;

comment on function public.toggle_business_status(uuid) is
  'Activar/desactivar un negocio desde la consola. Devuelve la fila actualizada.';

grant execute on function public.toggle_business_status(uuid) to authenticated;

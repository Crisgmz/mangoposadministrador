-- ============================================================================
-- Migración 0003 — RPCs del dashboard de la consola operadora
--
-- Tres funciones `SECURITY DEFINER` que la consola `mangopos_admin` consume
-- para alimentar la "Vista global". Todas validan que el caller esté en
-- `platform_operators` (vía `is_platform_operator()`) — fallan cerradas.
--
--   1) `get_platform_overview()`     — fila por negocio con todas las
--      métricas del día (ventas, ingresos, NCF, agente, impresión, sesiones,
--      mesas, plan).
--   2) `get_revenue_trend_12h()`     — 12 puntos horarios de ingresos
--      agregados a nivel plataforma para el RevenueChart.
--   3) `get_platform_alerts()`       — lista priorizada de alertas
--      (agentes desconectados, NCF crítico, membresías por vencer/vencidas).
--
-- Aplicar contra el mismo proyecto Supabase de `mangospos`.
-- Idempotente.
-- ============================================================================

set check_function_bodies = off;

-- ===========================================================================
-- 1) get_platform_overview()
-- ===========================================================================
create or replace function public.get_platform_overview()
returns table (
  id                  uuid,
  business_name       text,
  business_type       text,
  status              text,
  domain              text,
  plan_type           text,
  plan_end_date       timestamptz,
  agent_status        text,
  agent_last_seen     timestamptz,
  agent_name          text,
  sales_today         int,
  revenue_today       numeric,
  ncf_available       bigint,
  ncf_status          text,
  ncf_issued_today    int,
  print_jobs_today    int,
  print_failures_24h  int,
  open_sessions       int,
  open_tables         int
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today_start    timestamptz := (date_trunc('day', (now() at time zone 'America/Santo_Domingo'))) at time zone 'America/Santo_Domingo';
  v_24h_ago        timestamptz := now() - interval '24 hours';
  v_online_after   timestamptz := now() - interval '1 minute';
  v_late_after     timestamptz := now() - interval '10 minutes';
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado: requiere ser operador de plataforma' using errcode = '42501';
  end if;

  return query
  with agent_agg as (
    select an.business_id,
           max(an.last_seen)                                    as last_seen,
           string_agg(coalesce(an.name, an.site_code),
                      ' · ' order by an.last_seen desc nulls last) as names
      from public.agent_nodes an
     where an.is_active = true
     group by an.business_id
  ),
  rev_today as (
    select p.business_id,
           sum(p.amount)::numeric as revenue,
           count(*)::int          as sales
      from public.payments p
     where p.status = 'completed'
       and p.created_at >= v_today_start
     group by p.business_id
  ),
  ncf_avail as (
    select s.business_id,
           sum(greatest(s.range_end - s.current_number, 0))::bigint as available
      from public.ncf_sequences s
     where s.is_active = true
     group by s.business_id
  ),
  fd_today as (
    select fd.business_id, count(*)::int as cnt
      from public.fiscal_documents fd
     where fd.issued_at >= v_today_start
       and fd.status = 'active'
     group by fd.business_id
  ),
  print_agg as (
    select pj.business_id,
           count(*) filter (where pj.created_at >= v_today_start)                         as jobs_today,
           count(*) filter (where pj.created_at >= v_24h_ago and pj.status = 'failed')    as fail_24h
      from public.print_jobs pj
     where pj.created_at >= v_24h_ago
     group by pj.business_id
  ),
  open_sessions_agg as (
    select cr.business_id, count(*)::int as cnt
      from public.cash_register_sessions crs
      join public.cash_registers cr on cr.id = crs.cash_register_id
     where crs.status = 'open'
     group by cr.business_id
  ),
  open_tables_agg as (
    select ts.business_id, count(*)::int as cnt
      from public.table_sessions ts
     where ts.closed_at is null
       and ts.business_id is not null
     group by ts.business_id
  ),
  latest_membership as (
    select distinct on (m.business_id)
           m.business_id, m.plan_type, m.end_date
      from public.memberships m
     where m.status = 'active'
     order by m.business_id, m.created_at desc
  )
  select b.id,
         b.business_name,
         b.business_type,
         b.status,
         b.domain,
         lm.plan_type,
         lm.end_date,
         case
           when aa.last_seen is null              then 'SIN AGENTE'
           when aa.last_seen >= v_online_after    then 'EN LINEA'
           when aa.last_seen >= v_late_after      then 'TARDIO'
           else 'DESCONECTADO'
         end                                    as agent_status,
         aa.last_seen,
         aa.names,
         coalesce(rt.sales, 0)::int             as sales_today,
         coalesce(rt.revenue, 0)::numeric       as revenue_today,
         coalesce(na.available, 0)::bigint      as ncf_available,
         case
           when coalesce(na.available, 0) < 50  then 'CRITICO'
           when coalesce(na.available, 0) < 200 then 'ADVERTENCIA'
           else 'OK'
         end                                    as ncf_status,
         coalesce(ft.cnt, 0)::int               as ncf_issued_today,
         coalesce(pa.jobs_today, 0)::int        as print_jobs_today,
         coalesce(pa.fail_24h, 0)::int          as print_failures_24h,
         coalesce(os.cnt, 0)::int               as open_sessions,
         coalesce(ot.cnt, 0)::int               as open_tables
    from public.businesses b
    left join latest_membership lm  on lm.business_id = b.id
    left join agent_agg         aa  on aa.business_id = b.id
    left join rev_today         rt  on rt.business_id = b.id
    left join ncf_avail         na  on na.business_id = b.id
    left join fd_today          ft  on ft.business_id = b.id
    left join print_agg         pa  on pa.business_id = b.id
    left join open_sessions_agg os  on os.business_id = b.id
    left join open_tables_agg   ot  on ot.business_id = b.id
   order by b.business_name asc;
end;
$$;

comment on function public.get_platform_overview() is
  'Devuelve una fila por negocio con todas las métricas del dashboard. Solo operadores de plataforma.';

grant execute on function public.get_platform_overview() to authenticated;


-- ===========================================================================
-- 2) get_revenue_trend_12h()
-- ===========================================================================
create or replace function public.get_revenue_trend_12h()
returns table (
  hour          timestamptz,
  hour_label    text,
  revenue       numeric,
  transactions  int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado: requiere ser operador de plataforma' using errcode = '42501';
  end if;

  return query
  with hours as (
    select date_trunc('hour', now()) - (interval '1 hour' * gs) as hour_start
      from generate_series(11, 0, -1) gs
  )
  select h.hour_start as hour,
         to_char(h.hour_start at time zone 'America/Santo_Domingo', 'HH24:MI') as hour_label,
         coalesce(sum(p.amount), 0)::numeric as revenue,
         coalesce(count(p.id), 0)::int       as transactions
    from hours h
    left join public.payments p
      on p.created_at >= h.hour_start
     and p.created_at <  h.hour_start + interval '1 hour'
     and p.status = 'completed'
   group by h.hour_start
   order by h.hour_start asc;
end;
$$;

comment on function public.get_revenue_trend_12h() is
  'Ingresos plataforma por hora últimas 12h (12 puntos, ceros incluidos). Solo operadores de plataforma.';

grant execute on function public.get_revenue_trend_12h() to authenticated;


-- ===========================================================================
-- 3) get_platform_alerts()
-- ===========================================================================
create or replace function public.get_platform_alerts()
returns table (
  alert_type     text,
  severity       text,
  business_id    uuid,
  business_name  text,
  label          text,
  detail         text,
  reference_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_now           timestamptz := now();
  v_late_after    timestamptz := v_now - interval '10 minutes';
  v_expire_window timestamptz := v_now + interval '7 days';
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado: requiere ser operador de plataforma' using errcode = '42501';
  end if;

  return query
  with active_biz as (
    select b.id, b.business_name
      from public.businesses b
     where b.status = 'active'
  ),
  agent_status as (
    select ab.id  as business_id,
           ab.business_name,
           max(an.last_seen) as last_seen,
           string_agg(coalesce(an.name, an.site_code),
                      ' · ' order by an.last_seen desc nulls last) as names
      from active_biz ab
      left join public.agent_nodes an on an.business_id = ab.id and an.is_active = true
     group by ab.id, ab.business_name
  ),
  ncf_avail as (
    select ab.id as business_id,
           ab.business_name,
           coalesce(sum(greatest(s.range_end - s.current_number, 0)), 0)::bigint as available
      from active_biz ab
      left join public.ncf_sequences s on s.business_id = ab.id and s.is_active = true
     group by ab.id, ab.business_name
  ),
  latest_mem as (
    select distinct on (m.business_id)
           m.business_id, m.plan_type, m.end_date
      from public.memberships m
     where m.status = 'active'
     order by m.business_id, m.created_at desc
  )
  -- Agentes desconectados (sin agente o last_seen < hace 10 min)
  select 'agent_offline'::text                                as alert_type,
         'critical'::text                                     as severity,
         a.business_id,
         a.business_name,
         'Agente desconectado'::text                          as label,
         coalesce(a.names, 'Sin agente registrado')::text     as detail,
         a.last_seen                                          as reference_at
    from agent_status a
   where a.last_seen is null or a.last_seen < v_late_after

  union all

  -- NCF críticamente bajo (< 50 disponibles)
  select 'ncf_critical',
         'critical',
         n.business_id,
         n.business_name,
         'NCF críticamente bajo',
         format('Solo %s comprobantes disponibles', n.available),
         null
    from ncf_avail n
   where n.available < 50

  union all

  -- Membresías por vencer (próximos 7 días) o ya vencidas
  select 'plan_expiring',
         case when m.end_date < v_now then 'critical' else 'warning' end,
         m.business_id,
         ab.business_name,
         case when m.end_date < v_now then 'Membresía vencida' else 'Membresía por vencer' end,
         case
           when m.end_date < v_now
             then format('Vencida hace %s días', floor(extract(epoch from (v_now - m.end_date)) / 86400)::int)
           else format('Vence en %s días', floor(extract(epoch from (m.end_date - v_now)) / 86400)::int)
         end,
         m.end_date
    from latest_mem m
    join active_biz ab on ab.id = m.business_id
   where m.end_date is not null
     and m.end_date < v_expire_window

   order by 2 desc, 7 nulls last;  -- severity desc, then by reference_at
end;
$$;

comment on function public.get_platform_alerts() is
  'Alertas activas plataforma (agentes offline, NCF crítico, membresías por vencer/vencidas). Solo operadores de plataforma.';

grant execute on function public.get_platform_alerts() to authenticated;

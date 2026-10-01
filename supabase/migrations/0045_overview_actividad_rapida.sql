-- ===========================================================================
-- 0045 — Vista Global: "última actividad" sin recorrer toda la historia
--
-- POR QUÉ
-- `get_platform_overview()` calcula, por negocio, la última señal de uso:
-- último login, último pago y última apertura de caja. El bloque del último
-- pago agrupaba la tabla `payments` COMPLETA (149k filas / 84 MB medidos en
-- producción) en cada carga de la pantalla principal, y crece con cada mes de
-- operación.
--
-- Como negocios hay 71, sale mucho más barato preguntar el máximo uno por uno
-- que agrupar la tabla entera: son 71 búsquedas por índice.
--
-- REQUIERE
-- La migración `20260915_0010_indices_vista_global.sql` del repo mangospos,
-- que crea `idx_payments_completed_business_created`. Sin ese índice esto
-- igual funciona, pero no gana lo que tiene que ganar.
--
-- El resto de la función queda idéntico a 0008: mismas columnas, mismo
-- orden, mismos criterios. Solo cambia el CTE `last_payment`.
--
-- Idempotente (`create or replace`).
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
  open_tables         int,
  environment         text,
  activity_status     text,
  last_activity_at    timestamptz
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
  v_act_online     timestamptz := now() - interval '15 minutes';
  v_act_late       timestamptz := now() - interval '1 hour';
  v_act_recent     timestamptz := now() - interval '24 hours';
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
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
  ),
  -- Actividad — tres señales por negocio
  last_login as (
    select m.business_id, max(u.last_sign_in_at) as ts
      from public.memberships m
      join auth.users u on u.id = m.user_id
     where m.status = 'active'
     group by m.business_id
  ),
  last_payment as (
    -- Un max() por negocio (71) en vez de agrupar la tabla entera (149k).
    -- Postgres no convierte solo un `group by` en saltos por índice, así que
    -- la versión anterior recorría todos los pagos de la historia en cada
    -- carga. Así son 71 búsquedas contra
    -- idx_payments_completed_business_created (migración 0010 de mangospos).
    --
    -- Importante: prefijar `status` con el alias de la tabla. La función
    -- declara `status text` en `returns table`, lo que crea una variable
    -- implícita y un `where status = ...` queda ambiguo.
    select bb.id as business_id,
           (select max(pp.created_at)
              from public.payments pp
             where pp.business_id = bb.id
               and pp.status = 'completed') as ts
      from public.businesses bb
  ),
  last_open_session as (
    select cr.business_id, max(crs.opened_at) as ts
      from public.cash_register_sessions crs
      join public.cash_registers cr on cr.id = crs.cash_register_id
     group by cr.business_id
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
         coalesce(ot.cnt, 0)::int               as open_tables,
         b.environment,
         -- activity_status / last_activity_at (basado en señales reales de uso)
         case
           when greatest(ll.ts, lp.ts, los.ts) is null               then 'INACTIVO'
           when greatest(ll.ts, lp.ts, los.ts) >= v_act_online       then 'EN LINEA'
           when greatest(ll.ts, lp.ts, los.ts) >= v_act_late         then 'TARDIO'
           when greatest(ll.ts, lp.ts, los.ts) >= v_act_recent       then 'RECIENTE'
           else 'INACTIVO'
         end                                    as activity_status,
         greatest(ll.ts, lp.ts, los.ts)         as last_activity_at
    from public.businesses b
    left join latest_membership lm   on lm.business_id  = b.id
    left join agent_agg         aa   on aa.business_id  = b.id
    left join rev_today         rt   on rt.business_id  = b.id
    left join ncf_avail         na   on na.business_id  = b.id
    left join fd_today          ft   on ft.business_id  = b.id
    left join print_agg         pa   on pa.business_id  = b.id
    left join open_sessions_agg os   on os.business_id  = b.id
    left join open_tables_agg   ot   on ot.business_id  = b.id
    left join last_login        ll   on ll.business_id  = b.id
    left join last_payment      lp   on lp.business_id  = b.id
    left join last_open_session los  on los.business_id = b.id
   order by b.business_name asc;
end;
$$;

grant execute on function public.get_platform_overview() to authenticated;

notify pgrst, 'reload schema';

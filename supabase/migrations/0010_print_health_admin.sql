-- ============================================================================
-- Migración 0010 — Salud de Impresión (NOC, Fase 2 del PRD-12)
--
-- Provee al operador la vista cross-tenant del estado de la cola de
-- impresión: agentes con heartbeat, jobs no-terminales, top negocios con
-- fallas, y acciones para reintentar/cancelar trabajos.
--
--   1) Vista `v_admin_print_agents` — agent_nodes + business_name + estado
--      calculado del heartbeat.
--   2) Vista `v_admin_print_jobs` — print_jobs no-terminales + business_name
--      + printer name + edad en segundos.
--   3) RPCs:
--      - `get_admin_print_health()` — KPIs agregados.
--      - `get_admin_print_agents(env?)`
--      - `get_admin_print_jobs(env?, business_id?, status_filter?)`
--      - `get_admin_top_print_failures()` — ranking última hora por negocio.
--      - `admin_retry_print_job(job_id, reason)`
--      - `admin_cancel_print_job(job_id, reason)`
--
-- Idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Vista v_admin_print_agents
-- ---------------------------------------------------------------------------
drop view if exists public.v_admin_print_agents cascade;
create view public.v_admin_print_agents as
select
  an.id                                                  as agent_id,
  an.business_id,
  b.business_name,
  b.environment,
  an.site_code,
  an.name                                                as agent_name,
  an.is_active,
  an.last_seen,
  extract(epoch from (now() - an.last_seen))::bigint     as seconds_since_heartbeat,
  case
    when an.last_seen is null                              then 'NEVER'
    when an.last_seen >= now() - interval '60 seconds'     then 'ONLINE'
    when an.last_seen >= now() - interval '5 minutes'      then 'LATE'
    else                                                        'OFFLINE'
  end                                                    as health_status
from public.agent_nodes an
join public.businesses b on b.id = an.business_id;

comment on view public.v_admin_print_agents is
  'Agentes de impresión con estado de salud derivado del heartbeat: '
  '< 60s = ONLINE, 1-5min = LATE, > 5min = OFFLINE, sin último ping = NEVER.';


-- ---------------------------------------------------------------------------
-- 2) Vista v_admin_print_jobs (no-terminales + recientes terminales)
-- ---------------------------------------------------------------------------
drop view if exists public.v_admin_print_jobs cascade;
create view public.v_admin_print_jobs as
select
  pj.id,
  pj.business_id,
  b.business_name,
  b.environment,
  pj.kind,
  pj.status,
  pj.printer_id,
  pr.name                                              as printer_name,
  pj.ip,
  pj.port,
  pj.area_code,
  pj.retry_count,
  pj.priority,
  pj.last_error,
  pj.error,
  pj.next_retry_at,
  pj.claimed_at,
  pj.created_at,
  pj.printed_at,
  extract(epoch from (now() - pj.created_at))::bigint  as age_seconds
from public.print_jobs pj
join public.businesses     b  on b.id  = pj.business_id
left join public.printers  pr on pr.id = pj.printer_id;

comment on view public.v_admin_print_jobs is
  'Trabajos de impresión con info del negocio + impresora. La RPC filtra '
  'por estado y antigüedad.';


-- ---------------------------------------------------------------------------
-- 3) get_admin_print_health() — KPIs
-- ---------------------------------------------------------------------------
create or replace function public.get_admin_print_health()
returns table (
  agents_total       int,
  agents_online      int,
  agents_late        int,
  agents_offline     int,
  jobs_pending       int,
  jobs_printing      int,
  jobs_failed_1h     int,
  jobs_printed_1h    int
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
    (select count(*)::int from public.v_admin_print_agents),
    (select count(*)::int from public.v_admin_print_agents where health_status = 'ONLINE'),
    (select count(*)::int from public.v_admin_print_agents where health_status = 'LATE'),
    (select count(*)::int from public.v_admin_print_agents
       where health_status in ('OFFLINE','NEVER')),
    (select count(*)::int from public.print_jobs where status = 'pending'),
    (select count(*)::int from public.print_jobs where status = 'printing'),
    (select count(*)::int from public.print_jobs
       where status = 'failed' and created_at >= now() - interval '1 hour'),
    (select count(*)::int from public.print_jobs
       where status = 'printed' and printed_at >= now() - interval '1 hour');
end;
$$;

grant execute on function public.get_admin_print_health() to authenticated;


-- ---------------------------------------------------------------------------
-- 4) get_admin_print_agents(p_env)
-- ---------------------------------------------------------------------------
create or replace function public.get_admin_print_agents(p_env text default null)
returns setof public.v_admin_print_agents
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
  select * from public.v_admin_print_agents a
   where (p_env is null or a.environment = p_env)
   order by
     case a.health_status
       when 'OFFLINE' then 0
       when 'NEVER'   then 1
       when 'LATE'    then 2
       when 'ONLINE'  then 3
     end,
     a.last_seen asc nulls first,
     a.business_name asc;
end;
$$;

grant execute on function public.get_admin_print_agents(text) to authenticated;


-- ---------------------------------------------------------------------------
-- 5) get_admin_print_jobs(p_env, p_business_id, p_status_filter)
--
-- p_status_filter:
--   'non_terminal' (default) — pending + printing + failed (no cancelled/printed)
--   'pending'  | 'printing'  | 'failed'  | 'cancelled' | 'printed' | 'all'
-- ---------------------------------------------------------------------------
create or replace function public.get_admin_print_jobs(
  p_env           text default null,
  p_business_id   uuid default null,
  p_status_filter text default 'non_terminal',
  p_limit         int  default 200
)
returns setof public.v_admin_print_jobs
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
  select * from public.v_admin_print_jobs j
   where (p_env is null or j.environment = p_env)
     and (p_business_id is null or j.business_id = p_business_id)
     and case p_status_filter
           when 'non_terminal' then j.status in ('pending', 'printing', 'failed')
           when 'all'          then true
           else                     j.status = p_status_filter
         end
   order by
     case j.status
       when 'failed'   then 0
       when 'printing' then 1
       when 'pending'  then 2
       else                 3
     end,
     j.priority asc,
     j.created_at asc
   limit greatest(p_limit, 1);
end;
$$;

grant execute on function public.get_admin_print_jobs(text, uuid, text, int) to authenticated;


-- ---------------------------------------------------------------------------
-- 6) get_admin_top_print_failures() — top 10 negocios con más fallas última hora
-- ---------------------------------------------------------------------------
create or replace function public.get_admin_top_print_failures(p_limit int default 10)
returns table (
  business_id    uuid,
  business_name  text,
  environment    text,
  failed_count   int,
  last_failed_at timestamptz
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
  select b.id, b.business_name, b.environment,
         count(*)::int as failed_count,
         max(pj.created_at) as last_failed_at
    from public.print_jobs pj
    join public.businesses b on b.id = pj.business_id
   where pj.status = 'failed'
     and pj.created_at >= now() - interval '1 hour'
   group by b.id, b.business_name, b.environment
   order by failed_count desc, last_failed_at desc
   limit greatest(p_limit, 1);
end;
$$;

grant execute on function public.get_admin_top_print_failures(int) to authenticated;


-- ---------------------------------------------------------------------------
-- 7) admin_retry_print_job(job_id, reason)
--
-- Resetea el job a 'pending' para que un agente lo vuelva a tomar. Si está
-- en `printing` (atascado), lo libera. Si está `failed`, lo reintenta.
-- Mantiene `retry_count` (el natural lo incrementará el agente al fallar
-- de nuevo).
-- ---------------------------------------------------------------------------
create or replace function public.admin_retry_print_job(
  p_job_id uuid,
  p_reason text default null
)
returns public.print_jobs
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_job public.print_jobs;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  update public.print_jobs
     set status        = 'pending',
         next_retry_at = null,
         claimed_by    = null,
         claimed_at    = null,
         last_error    = null
   where id = p_job_id
     and status in ('failed', 'printing', 'pending')
  returning * into v_job;

  if v_job.id is null then
    raise exception 'Job % no existe o no es reintentable', p_job_id;
  end if;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'retry_print_job',
    'print_jobs',
    p_job_id,
    v_job.business_id,
    jsonb_build_object('reason', p_reason, 'retry_count', v_job.retry_count)
  );

  return v_job;
end;
$$;

grant execute on function public.admin_retry_print_job(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 8) admin_cancel_print_job(job_id, reason)
-- ---------------------------------------------------------------------------
create or replace function public.admin_cancel_print_job(
  p_job_id uuid,
  p_reason text
)
returns public.print_jobs
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_job public.print_jobs;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'La razón es requerida (mínimo 3 caracteres)'
      using errcode = '22023';
  end if;

  update public.print_jobs
     set status     = 'cancelled',
         last_error = coalesce(last_error, '') ||
                      ' [CANCELLED by NOC: ' || p_reason || ']'
   where id = p_job_id
     and status in ('pending', 'printing', 'failed')
  returning * into v_job;

  if v_job.id is null then
    raise exception 'Job % no existe o no se puede cancelar', p_job_id;
  end if;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'cancel_print_job',
    'print_jobs',
    p_job_id,
    v_job.business_id,
    jsonb_build_object('reason', p_reason, 'prev_status', v_job.status)
  );

  return v_job;
end;
$$;

grant execute on function public.admin_cancel_print_job(uuid, text) to authenticated;

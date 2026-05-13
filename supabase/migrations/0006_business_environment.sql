-- ============================================================================
-- Migración 0006 — Entorno de los negocios (production / sandbox)
--
-- Permite al operador marcar cuáles negocios son "production" (clientes reales)
-- vs "sandbox" (cuentas de prueba/QA). La consola pasará un filtro de entorno
-- en cada query para no contaminar métricas.
--
--   1) `businesses.environment` (production / sandbox, default production)
--   2) `set_business_environment(business_id, env)` para cambiarlo
--   3) Reescritura de los RPCs existentes para:
--      - devolver la columna `environment` (lo que el cliente filtra),
--      - aceptar `p_env` opcional cuando el cálculo es server-side
--        (revenue trend 12h y billing metrics).
--
-- Idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Columna en businesses
-- ---------------------------------------------------------------------------
alter table public.businesses
  add column if not exists environment text not null default 'production';

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'businesses_environment_check'
  ) then
    alter table public.businesses
      add constraint businesses_environment_check
      check (environment in ('production', 'sandbox'));
  end if;
end $$;

comment on column public.businesses.environment is
  'Marca si el negocio es de producción o sandbox (cuenta de prueba interna).';


-- ---------------------------------------------------------------------------
-- 1.5) DROPs requeridos
--
-- Postgres no permite cambiar el `returns table (...)` de una función con
-- `create or replace`. Soltamos las versiones previas (signatures originales
-- de las migraciones 0003 / 0004 / 0005) para poder recrearlas con el campo
-- `environment` extra. Idempotente.
-- ---------------------------------------------------------------------------
drop function if exists public.get_platform_overview();
drop function if exists public.get_revenue_trend_12h();
drop function if exists public.get_revenue_trend_12h(text);
drop function if exists public.get_platform_alerts();
drop function if exists public.get_critical_audit_logs(uuid, int);
drop function if exists public.get_recent_print_failures(uuid, int, int);
drop function if exists public.get_business_week_trend();
drop function if exists public.get_billing_overview();
drop function if exists public.get_billing_metrics();
drop function if exists public.get_billing_metrics(text);


-- ---------------------------------------------------------------------------
-- 2) RPC: set_business_environment
-- ---------------------------------------------------------------------------
create or replace function public.set_business_environment(
  p_business_id uuid,
  p_env         text
) returns public.businesses
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

  if p_env not in ('production', 'sandbox') then
    raise exception 'Entorno inválido: %', p_env using errcode = '22023';
  end if;

  update public.businesses
     set environment = p_env,
         updated_at = now()
   where id = p_business_id
  returning * into v_business;

  if v_business.id is null then
    raise exception 'Negocio % no existe', p_business_id;
  end if;

  return v_business;
end;
$$;

comment on function public.set_business_environment(uuid, text) is
  'Cambia un negocio entre production y sandbox.';

grant execute on function public.set_business_environment(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 3) get_platform_overview() — añade columna `environment` al final
-- ---------------------------------------------------------------------------
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
  environment         text
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
         b.environment
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

grant execute on function public.get_platform_overview() to authenticated;


-- ---------------------------------------------------------------------------
-- 4) get_revenue_trend_12h(p_env) — filtra server-side
-- ---------------------------------------------------------------------------
create or replace function public.get_revenue_trend_12h(p_env text default null)
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
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return query
  with hours as (
    select date_trunc('hour', now()) - (interval '1 hour' * gs) as hour_start
      from generate_series(11, 0, -1) gs
  ),
  filtered_biz as (
    select id from public.businesses
     where p_env is null or environment = p_env
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
     and (p_env is null or p.business_id in (select id from filtered_biz))
   group by h.hour_start
   order by h.hour_start asc;
end;
$$;

grant execute on function public.get_revenue_trend_12h(text) to authenticated;


-- ---------------------------------------------------------------------------
-- 5) get_platform_alerts() — añade `environment` al output
-- ---------------------------------------------------------------------------
create or replace function public.get_platform_alerts()
returns table (
  alert_type     text,
  severity       text,
  business_id    uuid,
  business_name  text,
  label          text,
  detail         text,
  reference_at   timestamptz,
  environment    text
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
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return query
  with active_biz as (
    select b.id, b.business_name, b.environment
      from public.businesses b
     where b.status = 'active'
  ),
  agent_status as (
    select ab.id  as business_id,
           ab.business_name,
           ab.environment,
           max(an.last_seen) as last_seen,
           string_agg(coalesce(an.name, an.site_code),
                      ' · ' order by an.last_seen desc nulls last) as names
      from active_biz ab
      left join public.agent_nodes an on an.business_id = ab.id and an.is_active = true
     group by ab.id, ab.business_name, ab.environment
  ),
  ncf_avail as (
    select ab.id as business_id,
           ab.business_name,
           ab.environment,
           coalesce(sum(greatest(s.range_end - s.current_number, 0)), 0)::bigint as available
      from active_biz ab
      left join public.ncf_sequences s on s.business_id = ab.id and s.is_active = true
     group by ab.id, ab.business_name, ab.environment
  ),
  latest_mem as (
    select distinct on (m.business_id)
           m.business_id, m.plan_type, m.end_date
      from public.memberships m
     where m.status = 'active'
     order by m.business_id, m.created_at desc
  )
  -- Agentes desconectados
  select 'agent_offline'::text                                as alert_type,
         'critical'::text                                     as severity,
         a.business_id,
         a.business_name,
         'Agente desconectado'::text                          as label,
         coalesce(a.names, 'Sin agente registrado')::text     as detail,
         a.last_seen                                          as reference_at,
         a.environment
    from agent_status a
   where a.last_seen is null or a.last_seen < v_late_after

  union all

  select 'ncf_critical',
         'critical',
         n.business_id,
         n.business_name,
         'NCF críticamente bajo',
         format('Solo %s comprobantes disponibles', n.available),
         null,
         n.environment
    from ncf_avail n
   where n.available < 50

  union all

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
         m.end_date,
         ab.environment
    from latest_mem m
    join active_biz ab on ab.id = m.business_id
   where m.end_date is not null
     and m.end_date < v_expire_window

   order by 2 desc, 7 nulls last;
end;
$$;

grant execute on function public.get_platform_alerts() to authenticated;


-- ---------------------------------------------------------------------------
-- 6) get_critical_audit_logs(p_business_id, p_limit) — añade `environment`
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
  created_at    timestamptz,
  environment   text
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
         al.created_at,
         b.environment
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

grant execute on function public.get_critical_audit_logs(uuid, int) to authenticated;


-- ---------------------------------------------------------------------------
-- 7) get_recent_print_failures(...) — añade `environment`
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
  created_at    timestamptz,
  environment   text
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
         pj.created_at,
         b.environment
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

grant execute on function public.get_recent_print_failures(uuid, int, int) to authenticated;


-- ---------------------------------------------------------------------------
-- 8) get_business_week_trend() — añade `environment`
-- ---------------------------------------------------------------------------
create or replace function public.get_business_week_trend()
returns table (
  business_id        uuid,
  business_name      text,
  week_revenue       numeric,
  last_week_revenue  numeric,
  trend_pct          numeric,
  environment        text
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
         end as trend_pct,
         b.environment
    from public.businesses b
    left join this_week tw on tw.business_id = b.id
    left join last_week lw on lw.business_id = b.id
   order by b.business_name;
end;
$$;

grant execute on function public.get_business_week_trend() to authenticated;


-- ---------------------------------------------------------------------------
-- 9) get_billing_overview() — añade `environment`
-- ---------------------------------------------------------------------------
create or replace function public.get_billing_overview()
returns table (
  id              uuid,
  invoice_number  text,
  business_id     uuid,
  business_name   text,
  plan_type       text,
  period_start    date,
  period_end      date,
  issue_date      timestamptz,
  due_date        timestamptz,
  amount          numeric,
  itbis           numeric,
  total           numeric,
  status          text,
  paid_at         timestamptz,
  payment_method  text,
  payment_reference text,
  environment     text
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
  select i.id, i.invoice_number, i.business_id, b.business_name,
         i.plan_type, i.period_start, i.period_end,
         i.issue_date, i.due_date,
         i.amount, i.itbis, i.total,
         i.status, i.paid_at, i.payment_method, i.payment_reference,
         b.environment
    from public.membership_invoices i
    join public.businesses b on b.id = i.business_id
   order by i.issue_date desc;
end;
$$;

grant execute on function public.get_billing_overview() to authenticated;


-- ---------------------------------------------------------------------------
-- 10) get_billing_metrics(p_env) — filtra server-side
-- ---------------------------------------------------------------------------
create or replace function public.get_billing_metrics(p_env text default null)
returns table (
  mrr             numeric,
  total_paid      numeric,
  total_pending   numeric,
  total_expired   numeric,
  count_pending   int,
  count_expired   int
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
  with filtered_biz as (
    select id from public.businesses
     where p_env is null or environment = p_env
  ),
  mrr_calc as (
    select coalesce(sum(public.plan_monthly_fee(lm.plan_type)), 0) as mrr_amount
      from (
        select distinct on (m.business_id)
               m.business_id, m.plan_type
          from public.memberships m
          join public.businesses b on b.id = m.business_id
         where m.status = 'active'
           and b.status = 'active'
           and (p_env is null or b.environment = p_env)
         order by m.business_id, m.created_at desc
      ) lm
  )
  select
    (select mrr_amount from mrr_calc)::numeric                                as mrr,
    coalesce(sum(mi.total) filter (where mi.status = 'paid'), 0)::numeric     as total_paid,
    coalesce(sum(mi.total) filter (where mi.status = 'pending'), 0)::numeric  as total_pending,
    coalesce(sum(mi.total) filter (where mi.status = 'expired'), 0)::numeric  as total_expired,
    coalesce(count(*) filter (where mi.status = 'pending'), 0)::int           as count_pending,
    coalesce(count(*) filter (where mi.status = 'expired'), 0)::int           as count_expired
  from public.membership_invoices mi
  where p_env is null
     or mi.business_id in (select id from filtered_biz);
end;
$$;

grant execute on function public.get_billing_metrics(text) to authenticated;

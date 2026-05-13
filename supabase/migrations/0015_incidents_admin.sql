-- ============================================================================
-- Migración 0015 — Sistema de Incidentes NOC (PRD-12, Fase 5 parte A)
--
-- Schema + RPCs para gestión manual de incidentes. La auto-detección y
-- el delivery a Telegram/webhooks se manejan en la migración 0016.
--
--   1) Tablas:
--      - `noc_incidents`     — histórico de incidentes (abiertos y cerrados).
--      - `noc_alert_rules`   — reglas configurables (esqueleto, sin lógica
--                              activa todavía; se llena cuando se conecten
--                              webhooks reales).
--      - `noc_webhooks`      — URLs de Telegram/Slack/email.
--
--   2) RPCs:
--      - `open_noc_incident(...)`            — abre un incidente.
--      - `close_noc_incident(id, note)`      — cierra con resolución.
--      - `get_admin_incidents(...)`          — listado con filtros.
--      - `get_admin_incident_summary()`      — KPIs.
--      - `get_admin_active_incidents_count()`— para badges de nav.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Tabla noc_incidents
-- ---------------------------------------------------------------------------
create table if not exists public.noc_incidents (
  id              uuid primary key default gen_random_uuid(),
  type            text not null,
  severity        text not null check (severity in ('info', 'warning', 'critical')),
  business_id     uuid references public.businesses(id) on delete set null,
  title           text not null,
  description     text,
  payload         jsonb,
  opened_at       timestamptz not null default now(),
  closed_at       timestamptz,
  resolved_by     uuid references auth.users(id),
  resolution_note text,
  -- Deduplica auto-detección: un dedupe_key igual no abre un incidente
  -- duplicado si ya hay uno abierto del mismo.
  dedupe_key      text,
  -- Permite que la auto-detección distinga incidentes generados por reglas
  -- de los abiertos manualmente.
  source          text not null default 'manual' check (source in ('manual', 'auto'))
);

create index if not exists noc_incidents_open_idx
  on public.noc_incidents (severity, opened_at desc)
  where closed_at is null;
create index if not exists noc_incidents_business_idx
  on public.noc_incidents (business_id, opened_at desc);
create index if not exists noc_incidents_type_idx
  on public.noc_incidents (type, opened_at desc);
create unique index if not exists noc_incidents_dedupe_active_idx
  on public.noc_incidents (dedupe_key)
  where closed_at is null and dedupe_key is not null;

alter table public.noc_incidents enable row level security;

drop policy if exists "noc_incidents operators read" on public.noc_incidents;
create policy "noc_incidents operators read"
on public.noc_incidents
for select
to authenticated
using (public.is_platform_operator());

comment on table public.noc_incidents is
  'Histórico de incidentes operativos detectados (auto o manual).';


-- ---------------------------------------------------------------------------
-- 2) Tabla noc_webhooks
-- ---------------------------------------------------------------------------
create table if not exists public.noc_webhooks (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  kind        text not null check (kind in ('telegram', 'slack', 'discord', 'email', 'generic')),
  url         text not null,
  config      jsonb,
  enabled     boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id) default auth.uid()
);

alter table public.noc_webhooks enable row level security;

drop policy if exists "noc_webhooks operators all" on public.noc_webhooks;
create policy "noc_webhooks operators all"
on public.noc_webhooks
for all
to authenticated
using (public.is_platform_operator())
with check (public.is_platform_operator());

comment on table public.noc_webhooks is
  'Destinos de alertas (Telegram bot, Slack incoming webhook, email, etc).';


-- ---------------------------------------------------------------------------
-- 3) Tabla noc_alert_rules
-- ---------------------------------------------------------------------------
create table if not exists public.noc_alert_rules (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  type             text not null,
  severity         text not null default 'warning'
                    check (severity in ('info', 'warning', 'critical')),
  -- SQL condition text — evaluado dinámicamente por la función auto-detect.
  -- Sintaxis sugerida: "select count(*) > 0 from v_admin_..."
  condition_sql    text,
  webhook_id       uuid references public.noc_webhooks(id) on delete set null,
  enabled          boolean not null default true,
  cooldown_minutes int not null default 5,
  last_fired_at    timestamptz,
  created_at       timestamptz not null default now()
);

alter table public.noc_alert_rules enable row level security;

drop policy if exists "noc_alert_rules operators all" on public.noc_alert_rules;
create policy "noc_alert_rules operators all"
on public.noc_alert_rules
for all
to authenticated
using (public.is_platform_operator())
with check (public.is_platform_operator());

comment on table public.noc_alert_rules is
  'Reglas configurables (con o sin SQL custom) que disparan alertas a webhooks.';


-- ---------------------------------------------------------------------------
-- 4) Vista v_admin_noc_incidents — agrega business_name
-- ---------------------------------------------------------------------------
drop view if exists public.v_admin_noc_incidents cascade;

create view public.v_admin_noc_incidents as
select
  i.id,
  i.type,
  i.severity,
  i.business_id,
  b.business_name,
  b.environment,
  i.title,
  i.description,
  i.payload,
  i.opened_at,
  i.closed_at,
  i.resolved_by,
  i.resolution_note,
  i.dedupe_key,
  i.source,
  case when i.closed_at is null then 'open' else 'closed' end as status,
  extract(epoch from (coalesce(i.closed_at, now()) - i.opened_at))::bigint as age_seconds,
  coalesce(
    nullif(trim(coalesce(e.first_name, '') || ' ' || coalesce(e.last_name, '')), ''),
    p.full_name
  ) as resolved_by_name
from public.noc_incidents i
left join public.businesses b on b.id = i.business_id
left join public.profiles p on p.id = i.resolved_by
left join public.employees e on e.user_id = i.resolved_by
                              and e.business_id = i.business_id;

comment on view public.v_admin_noc_incidents is
  'Incidentes NOC con info enriquecida del negocio y del operador que '
  'resolvió.';


-- ---------------------------------------------------------------------------
-- 5) open_noc_incident — abre un incidente, idempotente por dedupe_key
-- ---------------------------------------------------------------------------
create or replace function public.open_noc_incident(
  p_type        text,
  p_severity    text,
  p_business_id uuid default null,
  p_title       text default null,
  p_description text default null,
  p_payload     jsonb default null,
  p_dedupe_key  text default null,
  p_source      text default 'manual'
)
returns public.noc_incidents
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_inc public.noc_incidents;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_severity not in ('info', 'warning', 'critical') then
    raise exception 'Severity inválida: %', p_severity using errcode = '22023';
  end if;

  -- Idempotencia: si ya hay un incidente abierto con el mismo dedupe_key,
  -- devolverlo en lugar de crear duplicado.
  if p_dedupe_key is not null then
    select * into v_inc
      from public.noc_incidents
     where dedupe_key = p_dedupe_key
       and closed_at is null
     limit 1;
    if v_inc.id is not null then
      return v_inc;
    end if;
  end if;

  insert into public.noc_incidents (
    type, severity, business_id, title, description, payload,
    dedupe_key, source
  )
  values (
    p_type, p_severity, p_business_id,
    coalesce(p_title, p_type),
    p_description, p_payload,
    p_dedupe_key, coalesce(p_source, 'manual')
  )
  returning * into v_inc;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'open_incident',
    'noc_incidents',
    v_inc.id,
    p_business_id,
    jsonb_build_object('type', p_type, 'severity', p_severity, 'source', p_source)
  );

  return v_inc;
end;
$$;

grant execute on function public.open_noc_incident(
  text, text, uuid, text, text, jsonb, text, text
) to authenticated;


-- ---------------------------------------------------------------------------
-- 6) close_noc_incident — marca como cerrado con nota de resolución
-- ---------------------------------------------------------------------------
create or replace function public.close_noc_incident(
  p_incident_id uuid,
  p_note        text
)
returns public.noc_incidents
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_inc public.noc_incidents;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_note is null or length(trim(p_note)) < 3 then
    raise exception 'La nota de resolución es requerida (mínimo 3 caracteres)'
      using errcode = '22023';
  end if;

  update public.noc_incidents
     set closed_at      = now(),
         resolved_by    = auth.uid(),
         resolution_note = p_note
   where id = p_incident_id
     and closed_at is null
  returning * into v_inc;

  if v_inc.id is null then
    raise exception 'Incidente % no existe o ya está cerrado', p_incident_id;
  end if;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'close_incident',
    'noc_incidents',
    p_incident_id,
    v_inc.business_id,
    jsonb_build_object('note', p_note, 'type', v_inc.type)
  );

  return v_inc;
end;
$$;

grant execute on function public.close_noc_incident(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 7) get_admin_incidents — listado con filtros
--
-- Filtros:
--   status:    'all' | 'open' | 'closed' (default 'all')
--   severity:  'all' | 'info' | 'warning' | 'critical' (default 'all')
-- ---------------------------------------------------------------------------
create or replace function public.get_admin_incidents(
  p_env      text default null,
  p_status   text default 'all',
  p_severity text default 'all',
  p_limit    int  default 100
)
returns setof public.v_admin_noc_incidents
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
  select * from public.v_admin_noc_incidents i
   where (p_env is null or i.environment = p_env)
     and case p_status
           when 'open'   then i.closed_at is null
           when 'closed' then i.closed_at is not null
           else                true
         end
     and case p_severity
           when 'info'     then i.severity = 'info'
           when 'warning'  then i.severity = 'warning'
           when 'critical' then i.severity = 'critical'
           else                 true
         end
   order by
     -- Críticos abiertos primero, luego warnings abiertos, luego cerrados recientes.
     case when i.closed_at is null then 0 else 1 end,
     case i.severity
       when 'critical' then 0
       when 'warning'  then 1
       when 'info'     then 2
     end,
     i.opened_at desc
   limit greatest(p_limit, 1);
end;
$$;

grant execute on function public.get_admin_incidents(text, text, text, int) to authenticated;


-- ---------------------------------------------------------------------------
-- 8) get_admin_incident_summary — KPIs para el dashboard
-- ---------------------------------------------------------------------------
create or replace function public.get_admin_incident_summary(p_env text default null)
returns table (
  open_critical int,
  open_warning  int,
  open_info     int,
  open_total    int,
  closed_24h    int,
  oldest_open_seconds bigint
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
    (select count(*)::int from public.v_admin_noc_incidents i
      where i.status = 'open' and i.severity = 'critical'
        and (p_env is null or i.environment is null or i.environment = p_env)),
    (select count(*)::int from public.v_admin_noc_incidents i
      where i.status = 'open' and i.severity = 'warning'
        and (p_env is null or i.environment is null or i.environment = p_env)),
    (select count(*)::int from public.v_admin_noc_incidents i
      where i.status = 'open' and i.severity = 'info'
        and (p_env is null or i.environment is null or i.environment = p_env)),
    (select count(*)::int from public.v_admin_noc_incidents i
      where i.status = 'open'
        and (p_env is null or i.environment is null or i.environment = p_env)),
    (select count(*)::int from public.v_admin_noc_incidents i
      where i.closed_at is not null
        and i.closed_at >= now() - interval '24 hours'
        and (p_env is null or i.environment is null or i.environment = p_env)),
    (select coalesce(extract(epoch from (now() - min(i.opened_at)))::bigint, 0)
       from public.v_admin_noc_incidents i
      where i.status = 'open'
        and (p_env is null or i.environment is null or i.environment = p_env));
end;
$$;

grant execute on function public.get_admin_incident_summary(text) to authenticated;


-- ---------------------------------------------------------------------------
-- 9) get_admin_active_incidents_count — solo el número (badge)
-- ---------------------------------------------------------------------------
create or replace function public.get_admin_active_incidents_count(p_env text default null)
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
    return 0;
  end if;

  select count(*)::int into v_count
    from public.v_admin_noc_incidents i
   where i.closed_at is null
     and (p_env is null or i.environment is null or i.environment = p_env);

  return coalesce(v_count, 0);
end;
$$;

grant execute on function public.get_admin_active_incidents_count(text) to authenticated;

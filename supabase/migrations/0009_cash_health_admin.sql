-- ============================================================================
-- Migración 0009 — Salud de Cajas (NOC, Fase 1 del PRD-12)
--
-- Provee al operador la vista cross-tenant de la salud de cada sesión de
-- caja: cuál está abierta, cuánto saldo esperado lleva, edad, varianza.
-- Reutiliza la vista `v_cash_sessions_health` y la RPC `fn_force_close_cash_session`
-- que ya existen en mangospos (migraciones 0015 y 0016). Aquí solo agregamos:
--
--   1) `v_admin_cash_health` — extiende la vista base con `business_name`,
--      `environment` y otros joins útiles para el NOC.
--   2) `get_admin_cash_health(business_id?, filter?)` — devuelve la lista,
--      opcionalmente filtrada por negocio o por estado ('open' / 'needs_attention'
--      / 'closed_today' / 'variance_flagged').
--   3) `get_cash_session_detail(session_id)` — la sesión + el kardex de
--      cash_transactions.
--   4) `get_cash_session_kardex(session_id)` — solo los movimientos.
--   5) `admin_force_close_cash_session(session_id, end_amount, reason)` —
--      wrapper alrededor de la RPC existente con check `is_platform_operator`
--      y log a la tabla `noc_audit_log` (creada en esta migración).
--   6) Tabla mínima `noc_audit_log` (PRD §7.7 / §17.2) — solo acción + usuario
--      + recurso. Las otras tablas (incidents, alert_rules, webhooks) quedan
--      para fases posteriores.
--
-- Idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) noc_audit_log — registro mínimo de intervenciones del operador
-- ---------------------------------------------------------------------------
create table if not exists public.noc_audit_log (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id),
  action          text not null,
  target_resource text,
  target_id       uuid,
  business_id     uuid references public.businesses(id),
  payload         jsonb,
  created_at      timestamptz not null default now()
);

create index if not exists noc_audit_log_user_idx
  on public.noc_audit_log (user_id, created_at desc);
create index if not exists noc_audit_log_business_idx
  on public.noc_audit_log (business_id, created_at desc);
create index if not exists noc_audit_log_action_idx
  on public.noc_audit_log (action, created_at desc);

alter table public.noc_audit_log enable row level security;

drop policy if exists "noc_audit_log operators read" on public.noc_audit_log;
create policy "noc_audit_log operators read"
on public.noc_audit_log
for select
to authenticated
using (public.is_platform_operator());

-- Inserts solo desde RPCs (security definer); no policy de insert directa.

comment on table public.noc_audit_log is
  'Registro de cada intervención del operador desde la consola NOC.';


-- ---------------------------------------------------------------------------
-- 2) Vista v_admin_cash_health
-- ---------------------------------------------------------------------------
create or replace view public.v_admin_cash_health as
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
left join public.employees         e on e.user_id = h.user_id
left join public.profiles          p on p.id = h.user_id;

comment on view public.v_admin_cash_health is
  'Salud de cajas cross-tenant. Extiende v_cash_sessions_health con '
  'business_name, environment y nombre del cajero.';


-- ---------------------------------------------------------------------------
-- 3) get_admin_cash_health(p_business_id, p_filter)
--
-- `p_filter`:
--   'all'              — todas las sesiones (default)
--   'open'             — solo abiertas
--   'needs_attention'  — abiertas con `needs_attention = true`
--   'closed_today'     — cerradas en las últimas 24h
--   'variance_flagged' — cerradas con bandera de varianza
-- ---------------------------------------------------------------------------
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


-- ---------------------------------------------------------------------------
-- 4) get_cash_session_kardex(p_session_id)
-- ---------------------------------------------------------------------------
create or replace function public.get_cash_session_kardex(p_session_id uuid)
returns table (
  id               uuid,
  session_id       uuid,
  type             text,
  amount           numeric,
  description      text,
  related_order_id uuid,
  created_at       timestamptz
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
  select t.id, t.session_id, t.type, t.amount, t.description,
         t.related_order_id, t.created_at
    from public.cash_transactions t
   where t.session_id = p_session_id
   order by t.created_at asc;
end;
$$;

grant execute on function public.get_cash_session_kardex(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 5) get_cash_session_detail(p_session_id)
--    Devuelve la fila de la vista (1 fila max).
-- ---------------------------------------------------------------------------
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


-- ---------------------------------------------------------------------------
-- 6) admin_force_close_cash_session — wrapper con audit
-- ---------------------------------------------------------------------------
create or replace function public.admin_force_close_cash_session(
  p_session_id uuid,
  p_end_amount numeric,
  p_reason     text
)
returns public.cash_register_sessions
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_session public.cash_register_sessions;
  v_business_id uuid;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_reason is null or length(trim(p_reason)) < 5 then
    raise exception 'La razón es requerida (mínimo 5 caracteres)'
      using errcode = '22023';
  end if;

  -- Llama a la RPC existente en mangospos. `p_forced_by = auth.uid()`
  -- queda en el `notes` de la sesión vía la propia RPC.
  v_session := public.fn_force_close_cash_session(
    p_session_id := p_session_id,
    p_end_amount := p_end_amount,
    p_reason     := p_reason,
    p_forced_by  := auth.uid()
  );

  -- Audit log con el contexto del operador.
  select cr.business_id into v_business_id
    from public.cash_registers cr
   where cr.id = v_session.cash_register_id;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'force_close_cash_session',
    'cash_register_sessions',
    p_session_id,
    v_business_id,
    jsonb_build_object(
      'end_amount', p_end_amount,
      'reason',     p_reason,
      'difference', v_session.difference
    )
  );

  return v_session;
end;
$$;

grant execute on function public.admin_force_close_cash_session(uuid, numeric, text) to authenticated;

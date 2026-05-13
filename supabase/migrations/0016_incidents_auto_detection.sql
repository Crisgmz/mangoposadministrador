-- ============================================================================
-- Migración 0016 — Auto-detección de incidentes NOC (PRD-12, Fase 5 parte B)
--
-- Una sola función `noc_run_auto_detection()` que escanea todas las vistas
-- de salud y abre/cierra incidentes automáticamente. Diseñada para
-- ejecutarse vía `pg_cron` cada 1-5 minutos, o manualmente desde la UI
-- cuando el operador quiera refrescar.
--
-- Tipos de incidentes que detecta:
--   - `print_agent_down` — agente offline > 5 min.
--   - `ncf_critical`     — secuencia NCF con < 50 disponibles.
--   - `ncf_expired`      — secuencia NCF vencida.
--   - `ecf_rejected`     — e-CF rechazado por DGII.
--   - `ecf_stuck`        — e-CF pending/sent sin ACK > 1h.
--   - `cash_zombie`      — sesión de caja > 12h sin cerrar (needs_attention).
--   - `cash_variance`    — sesión cerrada con varianza flagged en últimas 24h.
--   - `table_zombie`     — sesión de mesa > 24h sin cerrar.
--   - `payment_stuck`    — orden partially_paid > 1h.
--
-- Cada incidente usa un `dedupe_key` único por entidad → no se duplica
-- mientras el problema sigue activo. Cuando el problema se resuelve (ya
-- no aparece en la vista correspondiente), la función cierra el incidente
-- automáticamente con nota `'[AUTO-RESOLVED]'`.
-- ============================================================================

create or replace function public.noc_run_auto_detection()
returns table (
  opened_count int,
  closed_count int
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_opened    int := 0;
  v_closed    int := 0;
  v_active_keys text[] := array[]::text[];
  v_row       record;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- ------------------------------------------------------------------
  -- 1) print_agent_down
  -- ------------------------------------------------------------------
  for v_row in
    select a.agent_id, a.business_id, a.business_name, a.agent_name,
           a.site_code, a.seconds_since_heartbeat
      from public.v_admin_print_agents a
     where a.health_status in ('OFFLINE', 'NEVER')
       and a.is_active = true
  loop
    v_active_keys := v_active_keys || ('print_agent_down:' || v_row.agent_id);
    insert into public.noc_incidents (
      type, severity, business_id, title, description, payload,
      dedupe_key, source
    )
    values (
      'print_agent_down', 'critical', v_row.business_id,
      'Agente desconectado',
      format('%s · %s sin heartbeat hace %ss',
             v_row.business_name,
             coalesce(v_row.agent_name, v_row.site_code),
             v_row.seconds_since_heartbeat),
      jsonb_build_object(
        'agent_id', v_row.agent_id,
        'site_code', v_row.site_code,
        'seconds_since_heartbeat', v_row.seconds_since_heartbeat
      ),
      'print_agent_down:' || v_row.agent_id,
      'auto'
    )
    on conflict (dedupe_key) where closed_at is null and dedupe_key is not null
    do nothing;
    if found then v_opened := v_opened + 1; end if;
  end loop;

  -- ------------------------------------------------------------------
  -- 2) ncf_critical / ncf_expired
  -- ------------------------------------------------------------------
  for v_row in
    select s.id, s.business_id, s.business_name, s.ncf_type, s.available,
           s.health_status, s.expiration_date
      from public.v_admin_ncf_sequences s
     where s.health_status in ('CRITICAL', 'EXPIRED')
       and s.is_active
  loop
    declare
      v_type     text := case v_row.health_status
                          when 'EXPIRED' then 'ncf_expired'
                          else                'ncf_critical' end;
      v_key      text := v_type || ':' || v_row.id;
      v_severity text := case v_row.health_status
                          when 'EXPIRED' then 'critical'
                          else                'critical' end;
    begin
      v_active_keys := v_active_keys || v_key;
      insert into public.noc_incidents (
        type, severity, business_id, title, description, payload,
        dedupe_key, source
      )
      values (
        v_type, v_severity, v_row.business_id,
        case v_type
          when 'ncf_expired' then 'Secuencia NCF vencida'
          else                    'NCF crítico'
        end,
        format('%s · %s · %s disponibles',
               v_row.business_name, v_row.ncf_type, v_row.available),
        jsonb_build_object(
          'sequence_id', v_row.id,
          'ncf_type', v_row.ncf_type,
          'available', v_row.available,
          'expiration_date', v_row.expiration_date
        ),
        v_key,
        'auto'
      )
      on conflict (dedupe_key) where closed_at is null and dedupe_key is not null
      do nothing;
      if found then v_opened := v_opened + 1; end if;
    end;
  end loop;

  -- ------------------------------------------------------------------
  -- 3) ecf_rejected / ecf_stuck
  -- ------------------------------------------------------------------
  for v_row in
    select p.id, p.business_id, p.business_name, p.ncf_number,
           p.problem_kind, p.total
      from public.v_admin_fiscal_problems p
     where p.problem_kind in ('REJECTED', 'STUCK')
  loop
    declare
      v_type text := case v_row.problem_kind
                       when 'REJECTED' then 'ecf_rejected'
                       else                 'ecf_stuck' end;
      v_key  text := v_type || ':' || v_row.id;
    begin
      v_active_keys := v_active_keys || v_key;
      insert into public.noc_incidents (
        type, severity, business_id, title, description, payload,
        dedupe_key, source
      )
      values (
        v_type, 'critical', v_row.business_id,
        case v_type
          when 'ecf_rejected' then 'e-CF rechazado por DGII'
          else                     'e-CF sin ACK > 1h'
        end,
        format('%s · NCF %s · %s', v_row.business_name, v_row.ncf_number, v_row.total),
        jsonb_build_object(
          'fiscal_document_id', v_row.id,
          'ncf_number', v_row.ncf_number,
          'total', v_row.total
        ),
        v_key,
        'auto'
      )
      on conflict (dedupe_key) where closed_at is null and dedupe_key is not null
      do nothing;
      if found then v_opened := v_opened + 1; end if;
    end;
  end loop;

  -- ------------------------------------------------------------------
  -- 4) cash_zombie
  -- ------------------------------------------------------------------
  for v_row in
    select c.session_id, c.business_id, c.business_name, c.caja_nombre,
           c.duracion_seconds, c.saldo_esperado_actual
      from public.v_admin_cash_health c
     where c.needs_attention = true
       and c.status = 'open'
  loop
    declare
      v_key text := 'cash_zombie:' || v_row.session_id;
    begin
      v_active_keys := v_active_keys || v_key;
      insert into public.noc_incidents (
        type, severity, business_id, title, description, payload,
        dedupe_key, source
      )
      values (
        'cash_zombie', 'warning', v_row.business_id,
        'Caja abierta > 12 h',
        format('%s · %s · hace %s h',
               v_row.business_name, v_row.caja_nombre,
               (v_row.duracion_seconds / 3600)),
        jsonb_build_object(
          'session_id', v_row.session_id,
          'duracion_seconds', v_row.duracion_seconds,
          'saldo_esperado', v_row.saldo_esperado_actual
        ),
        v_key,
        'auto'
      )
      on conflict (dedupe_key) where closed_at is null and dedupe_key is not null
      do nothing;
      if found then v_opened := v_opened + 1; end if;
    end;
  end loop;

  -- ------------------------------------------------------------------
  -- 5) cash_variance — sesión cerrada con varianza flagged últimas 24h
  -- ------------------------------------------------------------------
  for v_row in
    select c.session_id, c.business_id, c.business_name, c.caja_nombre,
           c.difference
      from public.v_admin_cash_health c
     where c.variance_flagged = true
       and c.status = 'closed'
       and c.closed_at >= now() - interval '24 hours'
  loop
    declare
      v_key text := 'cash_variance:' || v_row.session_id;
    begin
      v_active_keys := v_active_keys || v_key;
      insert into public.noc_incidents (
        type, severity, business_id, title, description, payload,
        dedupe_key, source
      )
      values (
        'cash_variance', 'warning', v_row.business_id,
        'Cierre de caja con varianza',
        format('%s · %s · diferencia %s',
               v_row.business_name, v_row.caja_nombre, v_row.difference),
        jsonb_build_object(
          'session_id', v_row.session_id,
          'difference', v_row.difference
        ),
        v_key,
        'auto'
      )
      on conflict (dedupe_key) where closed_at is null and dedupe_key is not null
      do nothing;
      if found then v_opened := v_opened + 1; end if;
    end;
  end loop;

  -- ------------------------------------------------------------------
  -- 6) table_zombie
  -- ------------------------------------------------------------------
  for v_row in
    select z.session_id, z.business_id, z.business_name,
           z.table_code, z.table_label, z.age_seconds, z.total_unpaid_estimated
      from public.v_admin_zombie_table_sessions z
  loop
    declare
      v_key text := 'table_zombie:' || v_row.session_id;
    begin
      v_active_keys := v_active_keys || v_key;
      insert into public.noc_incidents (
        type, severity, business_id, title, description, payload,
        dedupe_key, source
      )
      values (
        'table_zombie', 'warning', v_row.business_id,
        'Mesa abierta > 24 h',
        format('%s · Mesa %s · hace %s h · sin cobrar ~%s',
               v_row.business_name,
               coalesce(v_row.table_label, v_row.table_code, 'sin código'),
               (v_row.age_seconds / 3600),
               v_row.total_unpaid_estimated),
        jsonb_build_object(
          'session_id', v_row.session_id,
          'age_seconds', v_row.age_seconds,
          'unpaid', v_row.total_unpaid_estimated
        ),
        v_key,
        'auto'
      )
      on conflict (dedupe_key) where closed_at is null and dedupe_key is not null
      do nothing;
      if found then v_opened := v_opened + 1; end if;
    end;
  end loop;

  -- ------------------------------------------------------------------
  -- 7) payment_stuck
  -- ------------------------------------------------------------------
  for v_row in
    select s.order_id, s.business_id, s.business_name,
           s.table_code, s.table_label, s.remaining, s.age_seconds
      from public.v_admin_stuck_payments s
  loop
    declare
      v_key text := 'payment_stuck:' || v_row.order_id;
    begin
      v_active_keys := v_active_keys || v_key;
      insert into public.noc_incidents (
        type, severity, business_id, title, description, payload,
        dedupe_key, source
      )
      values (
        'payment_stuck', 'warning', v_row.business_id,
        'Pago parcial atascado',
        format('%s · Mesa %s · falta cobrar %s',
               v_row.business_name,
               coalesce(v_row.table_label, v_row.table_code, '—'),
               v_row.remaining),
        jsonb_build_object(
          'order_id', v_row.order_id,
          'remaining', v_row.remaining,
          'age_seconds', v_row.age_seconds
        ),
        v_key,
        'auto'
      )
      on conflict (dedupe_key) where closed_at is null and dedupe_key is not null
      do nothing;
      if found then v_opened := v_opened + 1; end if;
    end;
  end loop;

  -- ------------------------------------------------------------------
  -- Auto-cerrar incidentes cuya condición revirtió.
  -- Solo cierra incidentes con `source = 'auto'` para no pisar manuales.
  -- ------------------------------------------------------------------
  with closed as (
    update public.noc_incidents
       set closed_at       = now(),
           resolution_note = '[AUTO-RESOLVED] la condición ya no se cumple',
           resolved_by     = null
     where source = 'auto'
       and closed_at is null
       and dedupe_key is not null
       and not (dedupe_key = any (v_active_keys))
    returning id
  )
  select count(*) into v_closed from closed;

  -- Resumen.
  opened_count := v_opened;
  closed_count := v_closed;
  return next;
end;
$$;

comment on function public.noc_run_auto_detection() is
  'Escanea las vistas de salud y abre/cierra incidentes automáticamente. '
  'Diseñada para correr cada 1-5 minutos vía pg_cron o manualmente.';

grant execute on function public.noc_run_auto_detection() to authenticated;


-- ---------------------------------------------------------------------------
-- Setup de pg_cron (opcional — comentado).
--
-- Si tu Supabase tiene `pg_cron` habilitado, descomenta este bloque para
-- correr la auto-detección cada minuto. Si no, llama manualmente desde la
-- UI con el botón "Escanear ahora" cada vez que quieras refrescar.
-- ---------------------------------------------------------------------------
-- create extension if not exists pg_cron;
-- select cron.schedule(
--   'noc_auto_detect',
--   '*/1 * * * *',
--   $$select public.noc_run_auto_detection();$$
-- );

-- ============================================================================
-- Migración 0012 — Salud Fiscal NOC (PRD-12, Fase 3)
--
-- Cubre RF-FI-01 a RF-FI-05:
--   - e-CFs stuck en `ecf_status='sent'/'pending'` con >1h sin ACK.
--   - e-CFs rechazados en las últimas 24h.
--   - NCF sequences con disponibilidad baja o secuencia vencida.
--
-- NO incluye reenvío real a Alanube — ese flujo depende del integrador
-- externo. Aquí solo damos visibilidad y un `mark_for_retry` que el
-- operador puede usar para señalar manualmente que reintentó la emisión
-- por fuera del sistema. La integración Alanube full queda para una
-- iteración posterior.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Vista v_admin_fiscal_problems
--
-- Trae documentos fiscales que necesitan atención:
--   - Pendientes / enviados sin ACK >1h.
--   - Rechazados en las últimas 24h.
--   - Cancelados con motivo (para auditoría rápida).
-- ---------------------------------------------------------------------------
drop view if exists public.v_admin_fiscal_problems cascade;

create view public.v_admin_fiscal_problems as
select
  fd.id,
  fd.business_id,
  b.business_name,
  b.environment,
  fd.ncf_number,
  fd.ncf_type::text                                       as ncf_type,
  fd.customer_name,
  fd.customer_rnc,
  fd.total,
  fd.itbis_amount,
  fd.is_electronic,
  fd.ecf_status,
  fd.ecf_tracking_number,
  fd.status                                               as fiscal_status,
  fd.cancellation_reason,
  fd.issued_at,
  fd.ecf_signed_at,
  case
    when fd.status = 'cancelled'                                       then 'CANCELLED'
    when fd.ecf_status = 'rejected'                                    then 'REJECTED'
    when fd.is_electronic
         and fd.ecf_status in ('pending', 'sent')
         and fd.issued_at < now() - interval '1 hour'                  then 'STUCK'
    else                                                                    'OK'
  end                                                     as problem_kind,
  extract(epoch from (now() - fd.issued_at))::bigint      as age_seconds
from public.fiscal_documents fd
join public.businesses b on b.id = fd.business_id
where
  fd.status = 'cancelled'
  or fd.ecf_status = 'rejected'
  or (fd.is_electronic
      and fd.ecf_status in ('pending', 'sent')
      and fd.issued_at < now() - interval '1 hour');

comment on view public.v_admin_fiscal_problems is
  'Documentos fiscales con algún problema operativo: rechazados, '
  'stuck >1h sin ACK, o cancelados. Cualquier fila es candidata a '
  'intervención del NOC.';


-- ---------------------------------------------------------------------------
-- 2) Vista v_admin_ncf_sequences
--
-- NCF sequences con disponibilidad calculada y status por umbrales.
-- ---------------------------------------------------------------------------
drop view if exists public.v_admin_ncf_sequences cascade;

create view public.v_admin_ncf_sequences as
select
  s.id,
  s.business_id,
  b.business_name,
  b.environment,
  s.ncf_type::text                              as ncf_type,
  s.serie,
  s.prefix,
  s.range_start,
  s.range_end,
  s.current_number,
  greatest(s.range_end - s.current_number, 0)   as available,
  s.expiration_date,
  s.is_active,
  s.authorized_by,
  case
    when not s.is_active                                                then 'INACTIVE'
    when s.expiration_date is not null and s.expiration_date < current_date
                                                                        then 'EXPIRED'
    when s.expiration_date is not null
         and s.expiration_date < current_date + interval '15 days'      then 'EXPIRING_SOON'
    when greatest(s.range_end - s.current_number, 0) < 50               then 'CRITICAL'
    when greatest(s.range_end - s.current_number, 0) < 200              then 'WARNING'
    else                                                                     'OK'
  end                                           as health_status
from public.ncf_sequences s
join public.businesses b on b.id = s.business_id;

comment on view public.v_admin_ncf_sequences is
  'Secuencias NCF con disponibilidad y estado: OK, WARNING (<200), '
  'CRITICAL (<50), EXPIRING_SOON (<15 días), EXPIRED, INACTIVE.';


-- ---------------------------------------------------------------------------
-- 3) get_admin_fiscal_health() — KPIs
-- ---------------------------------------------------------------------------
create or replace function public.get_admin_fiscal_health(p_env text default null)
returns table (
  ecf_stuck            int,  -- pending/sent >1h
  ecf_rejected_24h     int,
  ecf_emitted_today    int,
  cancelled_today      int,
  ncf_sequences_total  int,
  ncf_critical         int,
  ncf_warning          int,
  ncf_expiring         int,
  ncf_expired          int
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_today_start timestamptz := (date_trunc('day', (now() at time zone 'America/Santo_Domingo'))) at time zone 'America/Santo_Domingo';
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  return query
  select
    (select count(*)::int
       from public.v_admin_fiscal_problems p
      where p.problem_kind = 'STUCK'
        and (p_env is null or p.environment = p_env)),
    (select count(*)::int
       from public.v_admin_fiscal_problems p
      where p.problem_kind = 'REJECTED'
        and p.issued_at >= now() - interval '24 hours'
        and (p_env is null or p.environment = p_env)),
    (select count(*)::int
       from public.fiscal_documents fd
       join public.businesses b on b.id = fd.business_id
      where fd.issued_at >= v_today_start
        and fd.status = 'active'
        and (p_env is null or b.environment = p_env)),
    (select count(*)::int
       from public.fiscal_documents fd
       join public.businesses b on b.id = fd.business_id
      where fd.status = 'cancelled'
        and fd.cancelled_at >= v_today_start
        and (p_env is null or b.environment = p_env)),
    (select count(*)::int
       from public.v_admin_ncf_sequences s
      where s.is_active
        and (p_env is null or s.environment = p_env)),
    (select count(*)::int
       from public.v_admin_ncf_sequences s
      where s.health_status = 'CRITICAL'
        and (p_env is null or s.environment = p_env)),
    (select count(*)::int
       from public.v_admin_ncf_sequences s
      where s.health_status = 'WARNING'
        and (p_env is null or s.environment = p_env)),
    (select count(*)::int
       from public.v_admin_ncf_sequences s
      where s.health_status = 'EXPIRING_SOON'
        and (p_env is null or s.environment = p_env)),
    (select count(*)::int
       from public.v_admin_ncf_sequences s
      where s.health_status = 'EXPIRED'
        and (p_env is null or s.environment = p_env));
end;
$$;

grant execute on function public.get_admin_fiscal_health(text) to authenticated;


-- ---------------------------------------------------------------------------
-- 4) get_admin_fiscal_problems(env, business_id, kind, limit)
--
-- kind:
--   'all'        — todos los problemas (default)
--   'stuck'      — pendientes/enviados >1h
--   'rejected'   — rechazados (sin filtro de tiempo extra; ya viene en la vista)
--   'cancelled'  — cancelados
-- ---------------------------------------------------------------------------
create or replace function public.get_admin_fiscal_problems(
  p_env         text default null,
  p_business_id uuid default null,
  p_kind        text default 'all',
  p_limit       int  default 100
)
returns setof public.v_admin_fiscal_problems
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
  select * from public.v_admin_fiscal_problems p
   where (p_env is null or p.environment = p_env)
     and (p_business_id is null or p.business_id = p_business_id)
     and case p_kind
           when 'stuck'     then p.problem_kind = 'STUCK'
           when 'rejected'  then p.problem_kind = 'REJECTED'
           when 'cancelled' then p.problem_kind = 'CANCELLED'
           else                  true
         end
   order by
     case p.problem_kind
       when 'REJECTED'  then 0
       when 'STUCK'     then 1
       when 'CANCELLED' then 2
       else                  3
     end,
     p.issued_at desc
   limit greatest(p_limit, 1);
end;
$$;

grant execute on function public.get_admin_fiscal_problems(text, uuid, text, int) to authenticated;


-- ---------------------------------------------------------------------------
-- 5) get_admin_ncf_sequences(env, status_filter)
--
-- status_filter:
--   'all', 'critical', 'warning', 'expiring', 'expired', 'inactive', 'ok'
-- ---------------------------------------------------------------------------
create or replace function public.get_admin_ncf_sequences(
  p_env           text default null,
  p_status_filter text default 'all'
)
returns setof public.v_admin_ncf_sequences
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
  select * from public.v_admin_ncf_sequences s
   where (p_env is null or s.environment = p_env)
     and case p_status_filter
           when 'critical' then s.health_status = 'CRITICAL'
           when 'warning'  then s.health_status = 'WARNING'
           when 'expiring' then s.health_status = 'EXPIRING_SOON'
           when 'expired'  then s.health_status = 'EXPIRED'
           when 'inactive' then s.health_status = 'INACTIVE'
           when 'ok'       then s.health_status = 'OK'
           else                  true
         end
   order by
     case s.health_status
       when 'EXPIRED'       then 0
       when 'CRITICAL'      then 1
       when 'EXPIRING_SOON' then 2
       when 'WARNING'       then 3
       when 'INACTIVE'      then 4
       else                      5
     end,
     s.available asc,
     s.business_name asc;
end;
$$;

grant execute on function public.get_admin_ncf_sequences(text, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 6) admin_mark_ecf_for_retry(doc_id, reason)
--
-- Marca un fiscal_document `rejected` o `stuck` para que el integrador
-- Alanube lo vuelva a procesar. Lo único que hace en BD: vuelve el
-- `ecf_status` a 'pending' para que la próxima iteración del worker
-- de Alanube lo retome. Registra en `noc_audit_log`.
-- ---------------------------------------------------------------------------
create or replace function public.admin_mark_ecf_for_retry(
  p_doc_id uuid,
  p_reason text
)
returns public.fiscal_documents
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_doc public.fiscal_documents;
begin
  if not public.is_platform_operator() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'La razón es requerida (mínimo 3 caracteres)'
      using errcode = '22023';
  end if;

  update public.fiscal_documents
     set ecf_status = 'pending'
   where id = p_doc_id
     and ecf_status in ('rejected', 'sent', 'pending')
     and status = 'active'
     and is_electronic = true
  returning * into v_doc;

  if v_doc.id is null then
    raise exception 'Documento % no existe o no es retryable', p_doc_id;
  end if;

  insert into public.noc_audit_log (
    user_id, action, target_resource, target_id, business_id, payload
  )
  values (
    auth.uid(),
    'mark_ecf_for_retry',
    'fiscal_documents',
    p_doc_id,
    v_doc.business_id,
    jsonb_build_object('reason', p_reason, 'ncf_number', v_doc.ncf_number)
  );

  return v_doc;
end;
$$;

grant execute on function public.admin_mark_ecf_for_retry(uuid, text) to authenticated;

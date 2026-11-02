-- Fase 2: identificar el proceso que envió el cobro de ECOBAR.
-- SOLO LECTURA. Ejecutar cada bloque SELECT por separado.
-- No ejecuta el cron, no llama a Azul ni devuelve claves/headers completos.

-- 1. Disponibilidad de cron/pg_net y columnas de las respuestas HTTP.
select
  now() at time zone 'America/Santo_Domingo' as ahora_ast,
  current_setting('pg_net.ttl', true) as retencion_http,
  to_regclass('cron.job') as tabla_jobs,
  to_regclass('cron.job_run_details') as tabla_ejecuciones,
  to_regclass('net._http_response') as tabla_respuestas_http,
  to_regclass('private.azul_cron_config') as tabla_config,
  (
    select array_agg(a.attname order by a.attnum)
    from pg_attribute a
    where a.attrelid = to_regclass('net._http_response')
      and a.attnum > 0 and not a.attisdropped
  ) as columnas_http;

-- 2. Job, rutina SQL y destino real configurado.
-- Ejecutar si cron.job y private.azul_cron_config existen.
-- command y prosrc solo se examinan para flags/hash; no se muestran.
with funcion as (
  select p.oid, p.prosrc
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'fn_azul_run_due_charges'
    and p.pronargs = 0
)
select
  j.jobid, j.jobname, j.schedule, j.active,
  position('fn_azul_run_due_charges' in j.command) > 0 as usa_rutina_esperada,
  md5(j.command) as command_hash,
  f.oid::regprocedure as funcion_sql,
  md5(f.prosrc) as function_body_hash,
  position('net.http_post' in f.prosrc) > 0 as usa_pg_net,
  position('subscription_effective_price_cents' in f.prosrc) > 0 as filtra_precio_cero,
  position('azul-charge-subscription' in f.prosrc) > 0 as invoca_funcion_cobro,
  regexp_replace(
    split_part(split_part(cfg.functions_base_url, '?', 1), '#', 1),
    '^(https?://)[^/@]+@', '\1[redactado]@'
  ) as functions_base_url,
  cfg.updated_at as config_updated_at
from cron.job j
left join funcion f on true
left join private.azul_cron_config cfg on cfg.id = true
where j.jobname ilike '%azul%' or j.command ilike '%azul%'
order by j.jobid;

-- 3. Ejecución del cron de las 03:00 AST del 27/10/2026.
-- "succeeded" confirma la ejecución SQL/encolado, no aprobación bancaria.
-- Ejecutar si cron.job_run_details existe.
select
  r.jobid, r.runid, j.jobname, r.status,
  r.start_time at time zone 'America/Santo_Domingo' as inicio_ast,
  r.end_time at time zone 'America/Santo_Domingo' as fin_ast,
  r.end_time - r.start_time as duracion
from cron.job_run_details r
left join cron.job j on j.jobid = r.jobid
where r.start_time >= timestamptz '2026-10-27 06:55:00+00'
  and r.start_time < timestamptz '2026-10-27 07:15:00+00'
  and (
    j.jobname ilike '%azul%'
    or r.command ilike '%fn_azul_run_due_charges%'
    or r.command ilike '%azul-charge-subscription%'
  )
order by r.start_time, r.runid;

-- 4. Respuestas HTTP retenidas del mismo intervalo.
-- Ejecutar si net._http_response existe. No devuelve headers ni content.
-- La ausencia de filas puede deberse a retención; no prueba ausencia de llamada.
-- Se leen columnas por nombre JSON para tolerar diferencias de pg_net.
with documentos as (
  select to_jsonb(r) as doc
  from net._http_response r
), respuestas as (
  select
    doc->>'id' as request_id,
    doc->>'status_code' as http_status,
    doc->>'content_type' as content_type,
    doc->>'timed_out' as timed_out,
    nullif(doc->>'error_msg', '') is not null as error_transporte,
    coalesce(doc->>'created', doc->>'created_at')::timestamptz as fecha,
    doc->>'content' as cuerpo
  from documentos
)
select
  request_id,
  fecha at time zone 'America/Santo_Domingo' as recibido_ast,
  http_status, content_type, timed_out, error_transporte,
  substring(cuerpo from '"charge_id"[[:space:]]*:[[:space:]]*"([0-9a-f-]+)"') as charge_id,
  substring(cuerpo from '"status"[[:space:]]*:[[:space:]]*"([a-z_]+)"') as estado,
  substring(cuerpo from '"code"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"') as codigo,
  position('0d47f52e-f3f2-4920-9f8e-8b46f2f5d1a4' in coalesce(cuerpo, '')) > 0 as es_cobro_ecobar,
  position('MP50656E2610271' in coalesce(cuerpo, '')) > 0 as contiene_orden,
  position('Invalid XML' in coalesce(cuerpo, '')) > 0 as contiene_invalid_xml
from respuestas
where fecha >= timestamptz '2026-10-27 06:55:00+00'
  and fecha < timestamptz '2026-10-27 07:15:00+00'
order by fecha, request_id
limit 100;

-- 5. Alcance del identificador ausente en los cobros creados el 27/10/2026.
-- Solo conteos agregados; no devuelve datos de otros negocios.
-- Un reintento puede actualizar una fila existente y no entra como fila nueva.
select
  count(*) as filas_creadas_el_27,
  count(*) filter (where custom_order_id is null) as sin_custom_order_id,
  count(*) filter (where custom_order_id is not null) as con_custom_order_id,
  count(*) filter (where status = 'approved') as aprobados,
  count(*) filter (where status = 'error') as errores
from public.azul_charges
where created_at >= timestamptz '2026-10-27 04:00:00+00'
  and created_at < timestamptz '2026-10-28 04:00:00+00';

-- 6. Estado actual del periodo afectado: ejecutar primero al retomar el caso.
-- Incluye filas nuevas y actualizaciones de la fila original por reintentos.
-- No llama a Azul ni muestra payloads completos.
select
  c.id, c.order_number, c.status, c.attempt_number,
  c.created_at at time zone 'America/Santo_Domingo' as creado_ast,
  c.updated_at at time zone 'America/Santo_Domingo' as actualizado_ast,
  c.attempted_at at time zone 'America/Santo_Domingo' as intento_ast,
  c.custom_order_id, c.azul_order_id, c.iso_code,
  c.response_code, c.error_description,
  e.received_at at time zone 'America/Santo_Domingo' as ultimo_evento_ast,
  case
    when e.id is null then null
    when e.raw_url like '%VerifyPayment%' then 'VerifyPayment'
    when e.raw_url like '%ProcessPayment%' then 'ProcessPayment'
    else 'otro'
  end as ultima_operacion
from public.azul_charges c
left join lateral (
  select ev.id, ev.received_at, ev.raw_url
  from public.azul_webhook_events ev
  where ev.related_charge_id = c.id
  order by ev.received_at desc, ev.id desc
  limit 1
) e on true
where c.business_id = 'fc3065c8-cb40-45ad-bec1-aecb388001c1'::uuid
  and c.billing_period_start = date '2026-10-27'
  and c.billing_period_end = date '2026-11-27'
order by c.attempted_at desc nulls last, c.id;

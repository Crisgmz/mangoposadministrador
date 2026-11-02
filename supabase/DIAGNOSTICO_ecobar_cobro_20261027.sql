-- ECOBAR AND LOUNGE: cobro RD$2,999.99, 27/10/2026, orden MP50656E2610271.
-- SOLO LECTURA. Ejecutar cada SELECT por separado en Supabase SQL Editor.
-- No devuelve tokens, encabezados, payloads completos ni números de tarjeta.
-- Un error sin ISO/operación Azul no prueba que no se haya debitado dinero.

-- 1. Cobro exacto y campos técnicos del request/response.
select
  c.id, c.business_id, c.membership_id, c.order_number,
  c.status, c.amount_cents / 100.0 as monto, c.currency_code,
  c.billing_period_start, c.billing_period_end, c.attempt_number,
  c.created_at at time zone 'America/Santo_Domingo' as creado_ast,
  c.updated_at at time zone 'America/Santo_Domingo' as actualizado_ast,
  c.attempted_at at time zone 'America/Santo_Domingo' as intento_ast,
  c.completed_at at time zone 'America/Santo_Domingo' as completado_ast,
  c.custom_order_id, c.azul_order_id, c.iso_code, c.response_code,
  c.response_message, c.error_description,
  jsonb_typeof(c.raw_response) as tipo_respuesta,
  c.raw_request->>'method' as request_method,
  c.raw_request->>'TrxType' as request_trx_type,
  c.raw_request->>'OrderNumber' as request_order,
  c.raw_request ? 'CustomOrderId' as request_tiene_custom_id,
  c.raw_request->>'CustomOrderId' as request_custom_order_id,
  c.raw_response->>'IsoCode' as response_iso,
  c.raw_response->>'ResponseCode' as response_code_raw,
  c.raw_response->>'ErrorDescription' as response_error,
  c.raw_response->>'AzulOrderId' as response_azul_order_id
from public.azul_charges c
where c.business_id = 'fc3065c8-cb40-45ad-bec1-aecb388001c1'::uuid
  and c.id = '0d47f52e-f3f2-4920-9f8e-8b46f2f5d1a4'::uuid;

-- 2. Bitácora asociada: regex tolera EXCEPTION y JSON truncado.
-- No convierte raw_body a JSON ni devuelve su contenido completo.
select
  e.id,
  e.received_at at time zone 'America/Santo_Domingo' as recibido_ast,
  e.event_type,
  case
    when e.raw_url like '%VerifyPayment%' then 'VerifyPayment'
    when e.raw_url like '%ProcessPayment%' then 'ProcessPayment'
    else 'otro'
  end as operacion,
  e.processed,
  left(e.processing_error, 500) as error,
  case
    when e.raw_body like 'EXCEPTION:%' then 'EXCEPTION'
    when left(ltrim(e.raw_body), 1) = '{' then 'objeto aparente'
    else 'otro texto'
  end as formato,
  substring(e.raw_body from '"IsoCode"[[:space:]]*:[[:space:]]*"([^"]*)"') as iso_code,
  substring(e.raw_body from '"ResponseCode"[[:space:]]*:[[:space:]]*"([^"]*)"') as response_code,
  substring(e.raw_body from '"Found"[[:space:]]*:[[:space:]]*"?([^",}[:space:]]+)') as found,
  substring(e.raw_body from '"AzulOrderId"[[:space:]]*:[[:space:]]*"([^"]*)"') as azul_order_id
from public.azul_webhook_events e
join public.azul_charges c on c.id = e.related_charge_id
where c.business_id = 'fc3065c8-cb40-45ad-bec1-aecb388001c1'::uuid
  and c.id = '0d47f52e-f3f2-4920-9f8e-8b46f2f5d1a4'::uuid
order by e.received_at, e.id;

-- 3. Suscripción actual e historial reciente del negocio.
-- Se separa la membership del historial: un cambio de ancla no oculta cobros.
with ultimos as (
  select
    c.id, c.membership_id, c.order_number, c.status,
    c.amount_cents / 100.0 as monto,
    c.billing_period_start, c.billing_period_end,
    c.attempt_number,
    c.attempted_at at time zone 'America/Santo_Domingo' as intento_ast,
    c.custom_order_id, c.azul_order_id, c.iso_code,
    count(*) over () as total_cobros_negocio
  from public.azul_charges c
  where c.business_id = 'fc3065c8-cb40-45ad-bec1-aecb388001c1'::uuid
  order by c.attempted_at desc, c.id
  limit 10
)
select
  m.id as suscripcion_actual,
  m.billing_status, m.current_attempt_number,
  m.current_period_start, m.current_period_end, m.next_billing_date,
  m.last_successful_charge_id, m.last_failed_charge_id,
  h.*
from public.businesses b
left join public.memberships m
  on m.business_id = b.id and m.is_billing_anchor = true
left join ultimos h on true
where b.id = 'fc3065c8-cb40-45ad-bec1-aecb388001c1'::uuid
order by h.intento_ast desc, h.id;

-- No rellenar custom_order_id retroactivamente con un valor inventado:
-- VerifyPayment solo sirve si ese identificador se envió realmente a Azul.

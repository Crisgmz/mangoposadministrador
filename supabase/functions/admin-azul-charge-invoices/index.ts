// Edge Function: admin-azul-charge-invoices
//
// Cobra a la tarjeta principal de UN negocio, en UN solo cargo, las facturas
// pendientes que eligió un OPERADOR desde la consola (con el precio que eligió
// en cada una). Tablas y RPC: migración 0054.
//
// POST /functions/v1/admin-azul-charge-invoices
// Auth: Bearer <JWT del operador>  (is_platform_operator() = true)
// Body:
//   { action: 'charge', invoice_ids: uuid[], totals?: {uuid: number}, request_key: uuid }
//   { action: 'verify', charge_id: uuid }
//
// charge:
//   1. fn_invoice_charge_reserve valida (mismo negocio, pendientes, tarjeta
//      verificada, sin otro cobro en curso) y crea el cobro `pending`. Si algo
//      no cuadra, nada llega a Azul. request_key repetido = el mismo cobro.
//   2. ProcessPayment Sale con el token (igual que el cobro mensual).
//   3. approved | declined | error → fn_invoice_charge_finalize (con
//      approved: facturas pagadas, vinculadas y el próximo cobro corrido, en
//      una transacción). Llamada caída o respuesta ambigua → queda `pending`
//      y se resuelve con verify. NUNCA se reintenta la venta a ciegas.
//
// verify: VerifyPayment por el CustomOrderId de un cobro `pending` (pasados 2
//   minutos). Found=0 → nunca llegó a Azul → `error` (se puede volver a cobrar).
//
// Bitácora: azul_webhook_events (respuesta cruda, igual que el cobro mensual;
// la pestaña Pagos cuenta las ventas desde ahí) + noc_audit_log (en el RPC).
//
// Env (las mismas que admin-azul-refund):
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
//   AZUL_PROXY_URL, AZUL_PROXY_AUTH_TOKEN, AZUL_MERCHANT_ID

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { AzulCallError, type AzulResponse, proxyCallUrl, sale, salePayload, verifyPayment } from './azul.ts';
import { classifySale, classifyVerify, invalidChargeRequest, isUuid } from './classify.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// VerifyPayment demasiado pronto puede no ver una venta que Azul todavía
// procesa; marcarla `error` dejaría cobrar dos veces.
const VERIFY_MIN_AGE_MS = 2 * 60 * 1000;

interface RequestBody {
  action?: string;
  invoice_ids?: unknown;
  totals?: unknown;
  request_key?: unknown;
  charge_id?: unknown;
}

interface Reserved {
  existing: boolean;
  charge_id: string;
  status: string;
  amount_cents: number;
  order_number: string;
  custom_order_id: string;
  payment_method_id: string;
  business_id: string;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/** Error con la forma `{ error: { code, message } }` que lee la consola. */
function fail(status: number, code: string, message: string, detail?: unknown): Response {
  return json({ error: { code, message, detail } }, status);
}

function requiredEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v || v.trim() === '') throw new Error(`Falta la variable de entorno ${name}`);
  return v;
}

function rd(cents: number): string {
  return `RD$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return fail(405, 'method_not_allowed', 'Use POST');

  try {
    const authHeader = req.headers.get('Authorization') ?? '';
    const jwt = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : '';
    if (!jwt) return fail(401, 'unauthorized', 'Falta el token de sesión');

    let body: RequestBody;
    try {
      body = await req.json();
    } catch {
      return fail(400, 'invalid_request', 'El body debe ser JSON');
    }

    const supabaseUrl = requiredEnv('SUPABASE_URL');

    // Solo operadores. Cliente con el JWT del usuario: auth.uid() = él.
    const userClient = createClient(supabaseUrl, requiredEnv('SUPABASE_ANON_KEY'), {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser(jwt);
    if (userErr || !userData.user) return fail(401, 'unauthorized', 'Sesión inválida');

    const { data: isOperator, error: opErr } = await userClient.rpc('is_platform_operator');
    if (opErr) return fail(500, 'rpc_error', 'No se pudo validar el operador', opErr.message);
    if (isOperator !== true) {
      return fail(403, 'forbidden', 'Solo operadores de la plataforma pueden cobrar a la tarjeta');
    }

    const service = createClient(supabaseUrl, requiredEnv('SUPABASE_SERVICE_ROLE_KEY'), {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    switch (body.action) {
      case 'charge':
        return await handleCharge(service, userData.user.id, body);
      case 'verify':
        return await handleVerify(service, userData.user.id, body);
      default:
        return fail(400, 'invalid_request', "action debe ser 'charge' o 'verify'");
    }
  } catch (e) {
    return fail(500, 'internal_error', `${e instanceof Error ? e.message : e}`);
  }
});

// ---------------------------------------------------------------------------
// charge
// ---------------------------------------------------------------------------
async function handleCharge(service: SupabaseClient, operatorId: string, body: RequestBody): Promise<Response> {
  const invalid = invalidChargeRequest(body);
  if (invalid) return fail(400, 'invalid_request', invalid);

  const { data: reservedRaw, error: reserveErr } = await service.rpc('fn_invoice_charge_reserve', {
    p_operator_id: operatorId,
    p_request_key: body.request_key,
    p_invoice_ids: body.invoice_ids,
    p_totals: body.totals ?? null,
  });
  if (reserveErr) {
    if (reserveErr.code === 'PGRST202' || reserveErr.code === '42883') {
      return fail(500, 'migration_missing', 'Falta aplicar la migración 0054_invoice_card_charge.sql.');
    }
    // 55P03: otro cobro de facturas del negocio sin confirmar.
    const status = reserveErr.code === '55P03' ? 409 : 422;
    const code = reserveErr.code === '55P03' ? 'charge_pending' : 'invalid_charge';
    return fail(status, code, reserveErr.message);
  }
  const reserved = reservedRaw as Reserved;

  // El mismo pedido repetido: no se vuelve a hablar con Azul.
  if (reserved.existing) {
    if (reserved.status === 'pending') {
      return fail(409, 'charge_pending', 'Este cobro ya se mandó a Azul y está sin confirmar. Verifícalo.', {
        charge_id: reserved.charge_id,
      });
    }
    return json({ status: reserved.status, charge_id: reserved.charge_id, idempotent: true });
  }

  const { data: pm, error: pmErr } = await service
    .from('azul_payment_methods')
    .select('data_vault_token')
    .eq('id', reserved.payment_method_id)
    .single();
  if (pmErr || !pm?.data_vault_token) {
    // Nada llegó a Azul: el cobro se cierra como no procesado.
    await finalize(service, reserved.charge_id, 'error', { ErrorDescription: 'Sin token de la tarjeta' }, operatorId);
    return fail(500, 'card_unavailable', 'No se pudo leer la tarjeta del negocio. No se cobró nada.');
  }

  const input = {
    amountCents: reserved.amount_cents,
    orderNumber: reserved.order_number,
    customOrderId: reserved.custom_order_id,
  };
  await service
    .from('azul_charges')
    .update({ raw_request: { method: 'ProcessPayment', ...salePayload(input), DataVaultToken: '***redacted***' } })
    .eq('id', reserved.charge_id);

  let result;
  try {
    result = await sale({ ...input, dataVaultToken: pm.data_vault_token as string });
  } catch (e) {
    const msg = e instanceof AzulCallError ? `${e.code}: ${e.message}` : String(e);
    await logWebservice(service, reserved.charge_id, 'ProcessPayment Sale', `EXCEPTION: ${msg}`, msg);
    // No se sabe si la venta llegó: queda pending para verificarla.
    return json({
      status: 'pending',
      charge_id: reserved.charge_id,
      amount_cents: reserved.amount_cents,
      message: 'No se supo si Azul cobró (la llamada se cayó). No vuelvas a cobrar: verifica en 2 minutos.',
    }, 202);
  }

  const azul = result.body;
  const outcome = classifySale(result.httpStatus, azul);
  await logWebservice(
    service,
    reserved.charge_id,
    'ProcessPayment Sale',
    JSON.stringify(azul),
    outcome === 'approved' ? null : (azul.ErrorDescription || azul.ResponseMessage || `iso_${azul.IsoCode}`),
  );

  if (outcome === 'pending') {
    return json({
      status: 'pending',
      charge_id: reserved.charge_id,
      amount_cents: reserved.amount_cents,
      message: 'Azul no dio una respuesta clara. No vuelvas a cobrar: verifica en 2 minutos.',
    }, 202);
  }
  return await finalizeResponse(service, reserved.charge_id, outcome, azul, operatorId, reserved.amount_cents);
}

// ---------------------------------------------------------------------------
// verify
// ---------------------------------------------------------------------------
async function handleVerify(service: SupabaseClient, operatorId: string, body: RequestBody): Promise<Response> {
  if (!isUuid(body.charge_id)) return fail(400, 'invalid_request', 'charge_id debe ser un UUID');

  const { data: charge, error } = await service
    .from('azul_charges')
    .select('id, status, source, amount_cents, custom_order_id, attempted_at')
    .eq('id', body.charge_id)
    .maybeSingle();
  if (error) return fail(500, 'db_error', 'No se pudo leer el cobro', error.message);
  if (!charge || charge.source !== 'invoices') return fail(404, 'not_found', 'Cobro de facturas no encontrado');
  if (charge.status !== 'pending') {
    return json({ status: charge.status, charge_id: charge.id, amount_cents: charge.amount_cents, already_final: true });
  }

  const age = Date.now() - new Date(charge.attempted_at as string).getTime();
  if (age < VERIFY_MIN_AGE_MS) {
    return fail(409, 'too_soon', 'Azul puede estar procesándolo todavía. Verifica en un momento.', {
      retry_in_seconds: Math.ceil((VERIFY_MIN_AGE_MS - age) / 1000),
    });
  }

  let result;
  try {
    result = await verifyPayment(charge.custom_order_id as string);
  } catch (e) {
    const msg = e instanceof AzulCallError ? `${e.code}: ${e.message}` : String(e);
    await logWebservice(service, charge.id, 'VerifyPayment', `EXCEPTION: ${msg}`, msg);
    return fail(502, 'verify_failed', 'No se pudo consultar a Azul. El cobro sigue sin confirmar.');
  }
  await logWebservice(service, charge.id, 'VerifyPayment', JSON.stringify(result.body), null);

  const outcome = classifyVerify(result.httpStatus, result.body);
  if (outcome === 'pending') {
    return json({
      status: 'pending',
      charge_id: charge.id,
      amount_cents: charge.amount_cents,
      message: 'Azul todavía no da una respuesta clara. Revísalo en el portal de Azul antes de volver a cobrar.',
    }, 202);
  }
  return await finalizeResponse(service, charge.id, outcome, result.body, operatorId, charge.amount_cents as number);
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------
function finalize(
  service: SupabaseClient,
  chargeId: string,
  outcome: 'approved' | 'declined' | 'error',
  azul: AzulResponse,
  operatorId: string,
) {
  return service.rpc('fn_invoice_charge_finalize', {
    p_charge_id: chargeId,
    p_outcome: outcome,
    p_azul: azul,
    p_operator_id: operatorId,
  });
}

async function finalizeResponse(
  service: SupabaseClient,
  chargeId: string,
  outcome: 'approved' | 'declined' | 'error',
  azul: AzulResponse,
  operatorId: string,
  amountCents: number,
): Promise<Response> {
  const { data, error } = await finalize(service, chargeId, outcome, azul, operatorId);
  if (error) {
    // Azul ya respondió (y con approved, cobró) pero no se pudo registrar: el
    // cobro sigue pending; verify lo vuelve a intentar sin cobrar de nuevo.
    console.error(`[admin-azul-charge-invoices] finalize ${chargeId} (${outcome}) falló: ${error.message}`);
    return fail(500, 'finalize_failed',
      `Azul respondió ${outcome === 'approved' ? 'APROBADO' : outcome} pero no se pudo registrar. ` +
        'No vuelvas a cobrar: usa Verificar.', { charge_id: chargeId });
  }
  const message = outcome === 'approved'
    ? `Azul aprobó el cobro de ${rd(amountCents)}.`
    : outcome === 'declined'
    ? `Azul rechazó la tarjeta: ${azul.ResponseMessage ?? azul.IsoCode ?? 'sin detalle'}. No se cobró nada.`
    : `Azul no procesó el cobro: ${azul.ErrorDescription || azul.ResponseMessage || 'sin detalle'}. No se cobró nada.`;
  return json({ ...(data as Record<string, unknown>), status: outcome, charge_id: chargeId, message });
}

// Misma bitácora forense que el cobro mensual (mangospos azul-charge-subscription):
// la pestaña Pagos cuenta las ventas aprobadas desde aquí.
async function logWebservice(
  service: SupabaseClient,
  chargeId: string,
  method: string,
  rawBody: string,
  processingError: string | null,
): Promise<void> {
  const { error } = await service.from('azul_webhook_events').insert({
    event_type: 'webservice_response',
    http_method: 'POST',
    raw_url: `${proxyCallUrl()} (${method})`,
    raw_body: rawBody.slice(0, 10000),
    related_charge_id: chargeId,
    processed: true,
    processing_error: processingError?.slice(0, 500) ?? null,
  });
  if (error) console.warn(`[admin-azul-charge-invoices] webhook log failed: ${error.message}`);
}

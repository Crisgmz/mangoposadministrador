// Edge Function: admin-azul-refund
//
// Reembolso total o parcial de un cobro de suscripción (azul_charges), pedido
// por un OPERADOR desde la consola. Tablas y RPC: migración 0046.
//
// POST /functions/v1/admin-azul-refund
// Auth: Bearer <JWT del operador>  (is_platform_operator() = true)
// Body:
//   { action: 'refund', charge_id: uuid, amount_cents: int, reason: string }
//   { action: 'verify', refund_id: uuid }
//
// refund:
//   1. fn_azul_refund_reserve bloquea el cobro, valida el saldo y crea el
//      reembolso en `pending`. Si el monto no cabe, nada llega a Azul.
//   2. ProcessPayment TrxType=Refund con AzulOrderId + OriginalDate.
//   3. approved | declined | error. Si la llamada se cae o la respuesta es
//      ambigua queda `pending` (sigue apartado) y se resuelve con verify.
//
// verify: VerifyPayment por el CustomOrderId de un reembolso `pending`.
//   Found=0 → nunca llegó a Azul → `error` (libera el saldo).
//
// Auditoría: noc_audit_log (quién, cuánto, por qué) + azul_webhook_events
// (respuesta cruda de Azul), igual que los cobros.
//
// Env (las mismas del stack que usan las funciones azul-* de mangospos):
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
//   AZUL_PROXY_URL, AZUL_PROXY_AUTH_TOKEN, AZUL_MERCHANT_ID

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { AzulCallError, type AzulResponse, refund, refundPayload, verifyPayment } from './azul.ts';
import { classifyRefundResult, isValidAmountCents, parseFound } from './classify.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const REFUND_COLUMNS =
  'id, charge_id, business_id, amount_cents, itbis_cents, currency_code, reason, status, ' +
  'order_number, custom_order_id, original_azul_order_id, original_date, azul_order_id, ' +
  'authorization_code, iso_code, response_code, response_message, error_description, ' +
  'requested_by, requested_at, completed_at, resolution_note';

// VerifyPayment demasiado pronto puede no ver una transacción que Azul todavía
// procesa; marcarla `error` liberaría el saldo.
const VERIFY_MIN_AGE_MS = 2 * 60 * 1000;
const MAX_REASON_LENGTH = 500;

interface RefundRow {
  id: string;
  charge_id: string;
  business_id: string;
  amount_cents: number;
  itbis_cents: number;
  reason: string;
  status: string;
  order_number: string;
  custom_order_id: string;
  original_azul_order_id: string;
  original_date: string;
  requested_at: string;
  [k: string]: unknown;
}

interface RequestBody {
  action?: string;
  charge_id?: string;
  amount_cents?: unknown;
  reason?: string;
  refund_id?: string;
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

function isUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

function rd(cents: number): string {
  return `RD$${(cents / 100).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

function requiredEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v || v.trim() === '') throw new Error(`Falta la variable de entorno ${name}`);
  return v;
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

    // 1. Solo operadores. Cliente con el JWT del usuario: auth.uid() = él.
    const userClient = createClient(supabaseUrl, requiredEnv('SUPABASE_ANON_KEY'), {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser(jwt);
    if (userErr || !userData.user) return fail(401, 'unauthorized', 'Sesión inválida');

    const { data: isOperator, error: opErr } = await userClient.rpc('is_platform_operator');
    if (opErr) return fail(500, 'rpc_error', 'No se pudo validar el operador', opErr.message);
    if (isOperator !== true) {
      return fail(403, 'forbidden', 'Solo operadores de la plataforma pueden reembolsar');
    }

    const service = createClient(supabaseUrl, requiredEnv('SUPABASE_SERVICE_ROLE_KEY'), {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    switch (body.action) {
      case 'refund':
        return await handleRefund(service, userData.user.id, body);
      case 'verify':
        return await handleVerify(service, userData.user.id, body);
      default:
        return fail(400, 'invalid_request', "action debe ser 'refund' o 'verify'");
    }
  } catch (e) {
    return fail(500, 'internal_error', `${e instanceof Error ? e.message : e}`);
  }
});

// ---------------------------------------------------------------------------
// refund
// ---------------------------------------------------------------------------
async function handleRefund(
  service: SupabaseClient,
  operatorId: string,
  body: RequestBody,
): Promise<Response> {
  const chargeId = body.charge_id?.trim() ?? '';
  if (!isUuid(chargeId)) return fail(400, 'invalid_request', 'charge_id inválido');
  if (!isValidAmountCents(body.amount_cents)) {
    return fail(400, 'invalid_request', 'amount_cents debe ser un entero mayor que cero');
  }
  const amountCents = body.amount_cents;
  const reason = body.reason?.trim() ?? '';
  if (!reason) return fail(400, 'invalid_request', 'La razón es obligatoria');
  if (reason.length > MAX_REASON_LENGTH) {
    return fail(400, 'invalid_request', `La razón no puede pasar de ${MAX_REASON_LENGTH} caracteres`);
  }

  // Reserva atómica: si no cabe, no se habla con Azul.
  const { data: reserved, error: reserveErr } = await service.rpc('fn_azul_refund_reserve', {
    p_charge_id: chargeId,
    p_amount_cents: amountCents,
    p_reason: reason,
    p_requested_by: operatorId,
  });
  if (reserveErr) {
    const status = reserveErr.code === 'P0002'
      ? 404
      : reserveErr.code === 'P0001' || reserveErr.code === '22023'
      ? 422
      : 500;
    return fail(status, 'refund_rejected', reserveErr.message);
  }
  const refundRow = reserved as RefundRow;

  const input = {
    azulOrderId: refundRow.original_azul_order_id,
    originalDate: refundRow.original_date,
    amountCents: refundRow.amount_cents,
    itbisCents: refundRow.itbis_cents,
    orderNumber: refundRow.order_number,
    customOrderId: refundRow.custom_order_id,
  };
  const rawRequest = { method: 'ProcessPayment', ...refundPayload(input) };

  let result;
  try {
    result = await refund(input);
  } catch (e) {
    // No sabemos si Azul lo procesó: queda `pending` (apartado) hasta verificar.
    const msg = e instanceof AzulCallError ? `${e.code}: ${e.message}` : String(e);
    await service
      .from('azul_refunds')
      .update({ error_description: msg.slice(0, 500), raw_request: rawRequest })
      .eq('id', refundRow.id);
    await logWebservice(service, refundRow.charge_id, 'ProcessPayment Refund', `EXCEPTION: ${msg}`, msg);
    await audit(service, operatorId, 'subscription.refund_unconfirmed', refundRow, { error: msg });
    return json(
      {
        ok: false,
        refund: await loadRefund(service, refundRow.id),
        message: 'No se pudo confirmar con Azul si el reembolso se procesó. Quedó pendiente: ' +
          'usa "Verificar con Azul" en unos minutos antes de intentarlo de nuevo.',
      },
      202,
    );
  }

  const azul = result.body;
  const outcome = classifyRefundResult(result.httpStatus, azul);
  await service
    .from('azul_refunds')
    .update({
      status: outcome,
      ...responseFields(azul),
      raw_request: rawRequest,
      raw_response: azul,
      completed_at: outcome === 'pending' ? null : new Date().toISOString(),
    })
    .eq('id', refundRow.id);

  await logWebservice(
    service,
    refundRow.charge_id,
    'ProcessPayment Refund',
    JSON.stringify(azul),
    outcome === 'approved'
      ? null
      : (azul.ErrorDescription || azul.ResponseMessage || `iso_${azul.IsoCode}`),
  );
  await audit(service, operatorId, `subscription.refund_${outcome}`, refundRow, {
    reason: refundRow.reason,
    iso_code: azul.IsoCode ?? null,
    response_message: azul.ResponseMessage ?? null,
    error_description: azul.ErrorDescription ?? null,
  });

  return json({
    ok: outcome === 'approved',
    refund: await loadRefund(service, refundRow.id),
    message: outcomeMessage(outcome, refundRow.amount_cents, azul),
  });
}

// ---------------------------------------------------------------------------
// verify
// ---------------------------------------------------------------------------
async function handleVerify(
  service: SupabaseClient,
  operatorId: string,
  body: RequestBody,
): Promise<Response> {
  const refundId = body.refund_id?.trim() ?? '';
  if (!isUuid(refundId)) return fail(400, 'invalid_request', 'refund_id inválido');

  const refundRow = await loadRefund(service, refundId);
  if (!refundRow) return fail(404, 'not_found', 'Reembolso no encontrado');

  if (refundRow.status !== 'pending') {
    return json({
      ok: refundRow.status === 'approved',
      refund: refundRow,
      message: 'Este reembolso ya estaba resuelto.',
    });
  }

  const ageMs = Date.now() - new Date(refundRow.requested_at).getTime();
  if (ageMs < VERIFY_MIN_AGE_MS) {
    return fail(
      409,
      'too_early',
      'Espera un par de minutos antes de verificar: Azul puede estar procesándolo todavía.',
    );
  }

  let result;
  try {
    result = await verifyPayment(refundRow.custom_order_id);
  } catch (e) {
    const msg = e instanceof AzulCallError ? `${e.code}: ${e.message}` : String(e);
    return fail(502, 'azul_unreachable', `No se pudo consultar a Azul: ${msg}`);
  }

  const azul = result.body;
  await logWebservice(service, refundRow.charge_id, 'VerifyPayment', JSON.stringify(azul), null);

  const found = result.httpStatus === 200 ? parseFound(azul.Found) : null;
  if (found === null) {
    return fail(
      502,
      'verify_inconclusive',
      'Azul no dio una respuesta clara. El reembolso sigue pendiente; revísalo en el portal de Azul.',
      { http_status: result.httpStatus, response_code: azul.ResponseCode ?? null },
    );
  }

  const nowIso = new Date().toISOString();
  let outcome: string;
  let note: string;
  if (!found) {
    outcome = 'error';
    note = `VerifyPayment ${nowIso}: Azul no tiene registro del reembolso (no llegó).`;
    await service
      .from('azul_refunds')
      .update({ status: outcome, completed_at: nowIso, resolution_note: note })
      .eq('id', refundRow.id);
  } else {
    outcome = classifyRefundResult(200, azul);
    const azulAmount = Number(azul.Amount);
    const amountNote = Number.isFinite(azulAmount) && azulAmount !== refundRow.amount_cents
      ? ` OJO: Azul reporta monto ${azulAmount} centavos.`
      : '';
    note = `VerifyPayment ${nowIso}: ${outcome}.${amountNote}`;
    await service
      .from('azul_refunds')
      .update({
        status: outcome,
        ...responseFields(azul),
        raw_response: azul,
        completed_at: outcome === 'pending' ? null : nowIso,
        resolution_note: note,
      })
      .eq('id', refundRow.id);
  }

  await audit(service, operatorId, `subscription.refund_verified_${outcome}`, refundRow, {
    found,
    note,
  });

  return json({
    ok: outcome === 'approved',
    refund: await loadRefund(service, refundRow.id),
    message: !found
      ? 'Azul no tiene registro de ese reembolso: no se devolvió nada. Ya puedes intentarlo de nuevo.'
      : outcomeMessage(outcome, refundRow.amount_cents, azul),
  });
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------
function responseFields(azul: AzulResponse) {
  return {
    azul_order_id: azul.AzulOrderId ?? null,
    authorization_code: azul.AuthorizationCode ?? null,
    response_code: azul.ResponseCode ?? null,
    iso_code: azul.IsoCode ?? null,
    response_message: azul.ResponseMessage ?? null,
    error_description: azul.ErrorDescription || null,
    rrn: azul.RRN ?? null,
  };
}

function outcomeMessage(outcome: string, amountCents: number, azul: AzulResponse): string {
  switch (outcome) {
    case 'approved':
      return `Reembolso de ${rd(amountCents)} aprobado por Azul.`;
    case 'declined':
      return `Azul rechazó el reembolso: ${azul.ResponseMessage || `código ${azul.IsoCode}`}. No se devolvió nada.`;
    case 'error':
      return `Azul no procesó el reembolso: ${
        azul.ErrorDescription || azul.ResponseMessage || 'error de validación'
      }. No se devolvió nada.`;
    default:
      return 'Azul no confirmó el resultado. Quedó pendiente: usa "Verificar con Azul" en unos minutos.';
  }
}

async function loadRefund(service: SupabaseClient, id: string): Promise<RefundRow | null> {
  const { data } = await service
    .from('azul_refunds')
    .select(REFUND_COLUMNS)
    .eq('id', id)
    .maybeSingle();
  return (data as RefundRow | null) ?? null;
}

// Misma bitácora forense que usan los cobros (mangospos azul-charge-subscription).
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
    raw_url: `azul-proxy /call (${method})`,
    raw_body: rawBody.slice(0, 10000),
    related_charge_id: chargeId,
    processed: true,
    processing_error: processingError?.slice(0, 500) ?? null,
  });
  if (error) console.warn(`[admin-azul-refund] webhook log failed: ${error.message}`);
}

// Best effort: si la auditoría falla, el reembolso igual quedó en azul_refunds
// con requested_by.
async function audit(
  service: SupabaseClient,
  operatorId: string,
  action: string,
  refundRow: RefundRow,
  extra: Record<string, unknown>,
): Promise<void> {
  const { error } = await service.from('noc_audit_log').insert({
    user_id: operatorId,
    action,
    target_resource: 'azul_refunds',
    target_id: refundRow.id,
    business_id: refundRow.business_id,
    payload: {
      charge_id: refundRow.charge_id,
      amount_cents: refundRow.amount_cents,
      original_azul_order_id: refundRow.original_azul_order_id,
      ...extra,
    },
  });
  if (error) console.warn(`[admin-azul-refund] audit failed: ${error.message}`);
}

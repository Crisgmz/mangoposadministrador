// Cliente mínimo de Azul para reembolsos, vía el sidecar mTLS `azul-proxy`.
//
// Autocontenido A PROPÓSITO: las funciones de mangospos comparten
// `supabase/functions/_shared/` en el servidor, pero este repo no lo despliega
// y su versión de `refund()` no manda OriginalDate. Depender de ese archivo
// ataría el reembolso a lo que haya copiado el último deploy de otro repo.
//
// Contrato del sidecar (mangospos/supabase/azul-proxy):
//   POST {AZUL_PROXY_URL}/call   header x-proxy-auth: AZUL_PROXY_AUTH_TOKEN
//   body { method: "ProcessPayment" | "VerifyPayment", body: {...} }
//   → { ok, httpStatus, durationMs, body } | { error: { code, message } }
// El sidecar agrega cert/key + Auth1/Auth2; acá no hay secretos de Azul.

export interface AzulResponse {
  IsoCode?: string;
  ResponseCode?: string;
  ResponseMessage?: string;
  ErrorDescription?: string;
  AuthorizationCode?: string;
  AzulOrderId?: string;
  CustomOrderId?: string;
  RRN?: string;
  DateTime?: string;
  Amount?: string;
  Found?: string | boolean;
  [k: string]: unknown;
}

export interface AzulCallResult {
  httpStatus: number;
  body: AzulResponse;
}

export class AzulCallError extends Error {
  constructor(message: string, readonly code: string) {
    super(message);
    this.name = 'AzulCallError';
  }
}

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v || v.trim() === '') throw new Error(`Falta la variable de entorno ${name}`);
  return v;
}

async function callAzul(
  method: 'ProcessPayment' | 'VerifyPayment',
  payload: Record<string, unknown>,
): Promise<AzulCallResult> {
  const url = `${env('AZUL_PROXY_URL').replace(/\/$/, '')}/call`;

  let res: Response;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-proxy-auth': env('AZUL_PROXY_AUTH_TOKEN'),
      },
      body: JSON.stringify({ method, body: payload }),
    });
  } catch (e) {
    throw new AzulCallError(
      `Sidecar inalcanzable: ${e instanceof Error ? e.message : String(e)}`,
      'sidecar_unreachable',
    );
  }

  const text = await res.text();
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new AzulCallError(
      `Sidecar respondió algo que no es JSON (http ${res.status}): ${text.slice(0, 300)}`,
      'sidecar_non_json',
    );
  }

  if (!res.ok || 'error' in parsed) {
    const err = (parsed.error ?? {}) as { code?: string; message?: string };
    throw new AzulCallError(
      `Sidecar: ${err.message ?? text.slice(0, 300)}`,
      err.code ?? 'sidecar_error',
    );
  }

  return {
    httpStatus: Number(parsed.httpStatus ?? 0),
    body: (parsed.body ?? {}) as AzulResponse,
  };
}

export interface RefundInput {
  /** AzulOrderId de la venta original. */
  azulOrderId: string;
  /** Fecha de la venta original, yyyymmdd. Obligatoria. */
  originalDate: string;
  amountCents: number;
  itbisCents: number;
  orderNumber: string;
  /** Único por reembolso: llave de VerifyPayment. */
  customOrderId: string;
}

/** Campos que se mandan a Azul, sin secretos (también van a raw_request). */
export function refundPayload(input: RefundInput): Record<string, string> {
  return {
    Channel: 'EC',
    Store: env('AZUL_MERCHANT_ID'),
    PosInputMode: 'E-Commerce',
    TrxType: 'Refund',
    Amount: String(input.amountCents),
    // Azul rechaza Itbis="0": sin impuesto va "000".
    Itbis: input.itbisCents > 0 ? String(input.itbisCents) : '000',
    CurrencyPosCode: '$',
    OrderNumber: input.orderNumber,
    AzulOrderId: input.azulOrderId,
    OriginalDate: input.originalDate,
    CustomOrderId: input.customOrderId,
    // AcquirerRefData va nulo en un Refund (doc Azul): no se envía.
  };
}

/**
 * Devolución (TrxType=Refund) de una venta ya liquidada — doc E-Commerce
 * WebServices v3.2. Parcial y múltiple permitido hasta el monto original,
 * dentro de 6 meses. El Void solo aplica en los primeros 20 minutos.
 */
export function refund(input: RefundInput): Promise<AzulCallResult> {
  return callAzul('ProcessPayment', refundPayload(input));
}

/** Última transacción con ese CustomOrderId (Found="0" si no existe). */
export function verifyPayment(customOrderId: string): Promise<AzulCallResult> {
  return callAzul('VerifyPayment', {
    Channel: 'EC',
    Store: env('AZUL_MERCHANT_ID'),
    CustomOrderId: customOrderId,
  });
}

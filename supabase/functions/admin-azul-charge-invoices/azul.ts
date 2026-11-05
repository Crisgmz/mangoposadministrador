// Cliente mínimo de Azul para cobrar facturas con el token de la tarjeta, vía
// el sidecar mTLS `azul-proxy`.
//
// Autocontenido como admin-azul-refund/azul.ts (las funciones de este repo no
// dependen de `_shared/` de mangospos). La venta es la MISMA que el cobro
// mensual de mangospos (`chargeWithToken` en _shared/azul-api.ts): Sale con
// DataVaultToken, MIT de orden permanente, sin 3DS.
//
// Contrato del sidecar (mangospos/supabase/azul-proxy):
//   POST {AZUL_PROXY_URL}/call   header x-proxy-auth: AZUL_PROXY_AUTH_TOKEN
//   body { method: "ProcessPayment" | "VerifyPayment", body: {...} }
//   → { ok, httpStatus, durationMs, body } | { error: { code, message } }

export interface AzulResponse {
  IsoCode?: string;
  ResponseCode?: string;
  ResponseMessage?: string;
  ErrorDescription?: string;
  AuthorizationCode?: string;
  AzulOrderId?: string;
  CustomOrderId?: string;
  RRN?: string;
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

/** URL del sidecar, tal como queda en la bitácora de las ventas. */
export function proxyCallUrl(): string {
  return `${env('AZUL_PROXY_URL').replace(/\/$/, '')}/call`;
}

async function callAzul(
  method: 'ProcessPayment' | 'VerifyPayment',
  payload: Record<string, unknown>,
): Promise<AzulCallResult> {
  let res: Response;
  try {
    res = await fetch(proxyCallUrl(), {
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
    throw new AzulCallError(`Sidecar: ${err.message ?? text.slice(0, 300)}`, err.code ?? 'sidecar_error');
  }

  return {
    httpStatus: Number(parsed.httpStatus ?? 0),
    body: (parsed.body ?? {}) as AzulResponse,
  };
}

export interface SaleInput {
  dataVaultToken: string;
  amountCents: number;
  orderNumber: string;
  /** Único por cobro: llave de VerifyPayment. */
  customOrderId: string;
}

/** Campos de la venta sin el token (también van a raw_request). */
export function salePayload(input: Omit<SaleInput, 'dataVaultToken'>): Record<string, string> {
  return {
    Channel: 'EC',
    Store: env('AZUL_MERCHANT_ID'),
    PosInputMode: 'E-Commerce',
    TrxType: 'Sale',
    Amount: String(input.amountCents),
    // Azul rechaza Itbis="0": sin impuesto separado va "000" (como el cobro mensual).
    Itbis: '000',
    CurrencyPosCode: '$',
    OrderNumber: input.orderNumber,
    CustomOrderId: input.customOrderId,
    AcquirerRefData: '1',
    // Cobro iniciado por el comercio con la tarjeta guardada (MIT), respaldado
    // por la transacción CIT de la tokenización. Sin tarjetahabiente: sin 3DS.
    merchantInitiatedIndicator: 'STANDING_ORDER',
    ForceNo3DS: '1',
  };
}

export function sale(input: SaleInput): Promise<AzulCallResult> {
  return callAzul('ProcessPayment', { ...salePayload(input), DataVaultToken: input.dataVaultToken });
}

/** Última transacción con ese CustomOrderId (Found="0" si no existe). */
export function verifyPayment(customOrderId: string): Promise<AzulCallResult> {
  return callAzul('VerifyPayment', {
    Channel: 'EC',
    Store: env('AZUL_MERCHANT_ID'),
    CustomOrderId: customOrderId,
  });
}

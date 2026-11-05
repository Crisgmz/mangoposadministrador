// Qué pasó con una venta (o su VerifyPayment).
//
// Regla de oro: ante la duda, `pending`. Un cobro pending bloquea otro cobro
// de facturas del negocio hasta verificarlo; marcarlo `error`/`declined` lo
// libera y deja volver a cobrar. Liberar una venta que Azul sí aprobó =
// cobrarle dos veces al cliente.

import type { AzulResponse } from './azul.ts';

export type SaleOutcome = 'approved' | 'declined' | 'error' | 'pending';

export function classifySale(httpStatus: number, body: AzulResponse): SaleOutcome {
  // Sin un 200 de Azul no sabemos qué pasó.
  if (httpStatus !== 200) return 'pending';
  if (body.IsoCode === '00') return 'approved';
  const responseCode = String(body.ResponseCode ?? '').trim().toUpperCase();
  // ISO8583 = el procesador la procesó; con IsoCode != 00 la rechazó.
  if (responseCode === 'ISO8583') return 'declined';
  // Doc Azul: 'Error = La transacción no fue procesada'.
  if (responseCode === 'ERROR') return 'error';
  return 'pending';
}

/**
 * VerifyPayment de una venta pending: `approved` (Azul la cobró), `error`
 * (Azul no la tiene o no la procesó: no se movió dinero) o `pending` (no se
 * puede saber todavía).
 */
export function classifyVerify(httpStatus: number, body: AzulResponse): 'approved' | 'error' | 'pending' {
  if (httpStatus !== 200) return 'pending';
  const found = parseFound(body.Found);
  if (found === null) return 'pending';
  // Con Found=0 Azul igual responde IsoCode "00" (la CONSULTA salió bien):
  // primero Found, el IsoCode solo si la encontró.
  if (!found) return 'error';
  if (body.IsoCode === '00') return 'approved';
  const responseCode = String(body.ResponseCode ?? '').trim().toUpperCase();
  if (responseCode === 'ISO8583' || responseCode === 'ERROR') return 'error';
  return 'pending';
}

/**
 * `Found` de VerifyPayment. Azul lo documenta como booleano pero en la práctica
 * llega como string ('0'/'1'/'true'/'false'). `null` = no se puede saber.
 */
export function parseFound(value: unknown): boolean | null {
  if (value === true || value === 1) return true;
  if (value === false || value === 0) return false;
  const s = String(value ?? '').trim().toLowerCase();
  if (s === '1' || s === 'true') return true;
  if (s === '0' || s === 'false') return false;
  return null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(s: unknown): s is string {
  return typeof s === 'string' && UUID_RE.test(s);
}

/**
 * Valida el pedido de la consola. Devuelve el error para el operador, o null.
 * El servidor (fn_invoice_charge_reserve) vuelve a validar todo; esto solo
 * evita mandarle basura.
 */
export function invalidChargeRequest(body: {
  invoice_ids?: unknown;
  totals?: unknown;
  request_key?: unknown;
}): string | null {
  if (!isUuid(body.request_key)) return 'request_key debe ser un UUID';
  const ids = body.invoice_ids;
  if (!Array.isArray(ids) || ids.length === 0) return 'Elige al menos una factura';
  if (ids.length > 60) return 'Máximo 60 facturas por cobro';
  if (!ids.every(isUuid)) return 'invoice_ids debe ser una lista de UUID';
  if (body.totals !== undefined && body.totals !== null) {
    if (typeof body.totals !== 'object' || Array.isArray(body.totals)) {
      return 'totals debe ser {factura: total}';
    }
    for (const [id, total] of Object.entries(body.totals as Record<string, unknown>)) {
      if (!ids.includes(id)) return `El precio de ${id} es de una factura que no se está cobrando`;
      if (typeof total !== 'number' || !Number.isFinite(total) || total < 0) {
        return `Precio inválido para ${id}`;
      }
    }
  }
  return null;
}

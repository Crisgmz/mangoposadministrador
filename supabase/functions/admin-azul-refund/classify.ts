// Clasificación de la respuesta de Azul para un Refund (o su VerifyPayment).
//
// Regla de oro: ante la duda, `pending`. Un `pending` sigue contando contra el
// saldo reembolsable del cobro; marcar `error`/`declined` lo libera y permite
// volver a reembolsar. Liberar un reembolso que Azul sí procesó = devolver el
// dinero dos veces.

import type { AzulResponse } from './azul.ts';

export type RefundOutcome = 'approved' | 'declined' | 'error' | 'pending';

export function classifyRefundResult(
  httpStatus: number,
  body: AzulResponse,
): RefundOutcome {
  // Sin un 200 de Azul no sabemos qué pasó.
  if (httpStatus !== 200) return 'pending';
  if (body.IsoCode === '00') return 'approved';
  const responseCode = String(body.ResponseCode ?? '').trim().toUpperCase();
  // ISO8583 = el procesador lo procesó; con IsoCode != 00 lo rechazó.
  if (responseCode === 'ISO8583') return 'declined';
  // Doc Azul: 'Error = La transacción no fue procesada'.
  if (responseCode === 'ERROR') return 'error';
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

/** `amount_cents` válido: entero positivo. */
export function isValidAmountCents(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value > 0;
}

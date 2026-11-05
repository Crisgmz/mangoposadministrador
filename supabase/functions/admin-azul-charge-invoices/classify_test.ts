// deno test admin-azul-charge-invoices/classify_test.ts
import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { classifySale, classifyVerify, invalidChargeRequest } from './classify.ts';

Deno.test('venta: solo IsoCode 00 es aprobada; la duda es pending', () => {
  assertEquals(classifySale(200, { IsoCode: '00', ResponseCode: 'ISO8583' }), 'approved');
  assertEquals(classifySale(200, { IsoCode: '51', ResponseCode: 'ISO8583' }), 'declined');
  assertEquals(classifySale(200, { IsoCode: '', ResponseCode: 'Error' }), 'error');
  assertEquals(classifySale(200, { IsoCode: '', ResponseCode: '' }), 'pending');
  assertEquals(classifySale(504, { IsoCode: '00' }), 'pending');
});

Deno.test('verify: Found manda antes que IsoCode', () => {
  // Found=0 llega con IsoCode 00 (la consulta salió bien): no se cobró.
  assertEquals(classifyVerify(200, { Found: '0', IsoCode: '00' }), 'error');
  assertEquals(classifyVerify(200, { Found: '1', IsoCode: '00' }), 'approved');
  assertEquals(classifyVerify(200, { Found: true, IsoCode: '05', ResponseCode: 'ISO8583' }), 'error');
  assertEquals(classifyVerify(200, { Found: 'quizás' }), 'pending');
  assertEquals(classifyVerify(500, { Found: '1', IsoCode: '00' }), 'pending');
});

Deno.test('pedido: llave, facturas y precios', () => {
  const id = '00000000-0000-0000-0000-0000000000a1';
  const key = '00000000-0000-0000-0000-0000000000f1';
  assertEquals(invalidChargeRequest({ invoice_ids: [id], request_key: key }), null);
  assertEquals(invalidChargeRequest({ invoice_ids: [id], request_key: key, totals: { [id]: 1000 } }), null);
  assertEquals(invalidChargeRequest({ invoice_ids: [id], request_key: 'x' }), 'request_key debe ser un UUID');
  assertEquals(invalidChargeRequest({ invoice_ids: [], request_key: key }), 'Elige al menos una factura');
  assertEquals(
    invalidChargeRequest({ invoice_ids: [id], request_key: key, totals: { [key]: 5 } }),
    `El precio de ${key} es de una factura que no se está cobrando`,
  );
  assertEquals(
    invalidChargeRequest({ invoice_ids: [id], request_key: key, totals: { [id]: -1 } }),
    `Precio inválido para ${id}`,
  );
});

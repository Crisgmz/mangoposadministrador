import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { classifyRefundResult, isValidAmountCents, parseFound } from './classify.ts';

Deno.test('aprobado: 200 + IsoCode 00', () => {
  assertEquals(
    classifyRefundResult(200, { IsoCode: '00', ResponseCode: 'ISO8583' }),
    'approved',
  );
});

Deno.test('declinado: procesado por ISO8583 con IsoCode != 00', () => {
  assertEquals(
    classifyRefundResult(200, { IsoCode: '05', ResponseCode: 'ISO8583' }),
    'declined',
  );
});

Deno.test('error: Azul no lo procesó (ResponseCode Error)', () => {
  assertEquals(
    classifyRefundResult(200, {
      IsoCode: '',
      ResponseCode: 'Error',
      ErrorDescription: 'VALIDATION_ERROR:OriginalDate',
    }),
    'error',
  );
});

Deno.test('pending: HTTP no-200 aunque diga 00 — no liberar el saldo', () => {
  assertEquals(
    classifyRefundResult(502, { IsoCode: '00', ResponseCode: 'ISO8583' }),
    'pending',
  );
  assertEquals(classifyRefundResult(500, {}), 'pending');
});

Deno.test('pending: respuesta sin ResponseCode reconocible', () => {
  assertEquals(classifyRefundResult(200, { IsoCode: '' }), 'pending');
  assertEquals(classifyRefundResult(200, { ResponseCode: 'Otro' }), 'pending');
});

Deno.test('parseFound: formatos que devuelve Azul', () => {
  assertEquals(parseFound('1'), true);
  assertEquals(parseFound('true'), true);
  assertEquals(parseFound(true), true);
  assertEquals(parseFound('0'), false);
  assertEquals(parseFound('False'), false);
  assertEquals(parseFound(false), false);
  assertEquals(parseFound(undefined), null);
  assertEquals(parseFound('quizás'), null);
});

Deno.test('isValidAmountCents: enteros positivos solamente', () => {
  assertEquals(isValidAmountCents(179999), true);
  assertEquals(isValidAmountCents(0), false);
  assertEquals(isValidAmountCents(-5), false);
  assertEquals(isValidAmountCents(1799.99), false);
  assertEquals(isValidAmountCents('179999'), false);
});

// Contrato con el sidecar azul-proxy, contra un sidecar falso local.
// deno test --allow-net --allow-env admin-azul-refund/azul_test.ts
import { assertEquals, assertRejects } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { AzulCallError, refund, verifyPayment } from './azul.ts';

interface Received {
  auth: string | null;
  payload: { method: string; body: Record<string, string> };
}

async function withFakeProxy(
  respond: (r: Received) => Response,
  run: (received: Received[]) => Promise<void>,
) {
  const received: Received[] = [];
  const ac = new AbortController();
  const server = Deno.serve(
    { port: 0, signal: ac.signal, onListen: () => {} },
    async (req) => {
      const r = { auth: req.headers.get('x-proxy-auth'), payload: await req.json() };
      received.push(r);
      return respond(r);
    },
  );
  Deno.env.set('AZUL_PROXY_URL', `http://127.0.0.1:${server.addr.port}/`);
  Deno.env.set('AZUL_PROXY_AUTH_TOKEN', 'tok-test');
  Deno.env.set('AZUL_MERCHANT_ID', '39038540035');
  try {
    await run(received);
  } finally {
    ac.abort();
    await server.finished;
  }
}

const INPUT = {
  azulOrderId: '376998587',
  originalDate: '20260916',
  amountCents: 179999,
  itbisCents: 0,
  orderNumber: 'RFABC1234567890',
  customOrderId: 'mprf-abc',
};

Deno.test('refund manda los campos obligatorios de Azul', async () => {
  await withFakeProxy(
    () => Response.json({ ok: true, httpStatus: 200, durationMs: 1, body: { IsoCode: '00' } }),
    async (received) => {
      const res = await refund(INPUT);
      assertEquals(res.httpStatus, 200);
      assertEquals(res.body.IsoCode, '00');

      assertEquals(received.length, 1);
      assertEquals(received[0].auth, 'tok-test');
      assertEquals(received[0].payload.method, 'ProcessPayment');
      const b = received[0].payload.body;
      assertEquals(b.TrxType, 'Refund');
      assertEquals(b.Store, '39038540035');
      assertEquals(b.Amount, '179999');
      assertEquals(b.Itbis, '000');
      assertEquals(b.AzulOrderId, '376998587');
      assertEquals(b.OriginalDate, '20260916');
      assertEquals(b.CustomOrderId, 'mprf-abc');
      assertEquals('AcquirerRefData' in b, false);
    },
  );
});

Deno.test('verifyPayment consulta por CustomOrderId', async () => {
  await withFakeProxy(
    () => Response.json({ ok: true, httpStatus: 200, durationMs: 1, body: { IsoCode: '00', Found: '0' } }),
    async (received) => {
      const res = await verifyPayment('mprf-abc');
      assertEquals(res.body.Found, '0');
      assertEquals(received[0].payload.method, 'VerifyPayment');
      assertEquals(received[0].payload.body.CustomOrderId, 'mprf-abc');
    },
  );
});

Deno.test('error del sidecar lanza AzulCallError (nunca parece aprobado)', async () => {
  await withFakeProxy(
    () => Response.json({ error: { code: 'upstream_timeout', message: 'Azul no respondió' } }, { status: 502 }),
    async () => {
      await assertRejects(() => refund(INPUT), AzulCallError, 'Azul no respondió');
    },
  );
});

Deno.test('sidecar que no devuelve JSON lanza AzulCallError', async () => {
  await withFakeProxy(
    () => new Response('<html>502</html>', { status: 502 }),
    async () => {
      await assertRejects(() => refund(INPUT), AzulCallError);
    },
  );
});

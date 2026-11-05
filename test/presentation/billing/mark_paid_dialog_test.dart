// El diálogo de pago muestra, ANTES de confirmar, qué cobros con tarjeta se
// corren — y el pago real sale sin dry_run. Es la garantía de que el operador
// no descubre el efecto sobre la tarjeta después.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mangopos_administrador/core/format/formatters.dart';
import 'package:mangopos_administrador/data/repositories/billing_repository.dart';
import 'package:mangopos_administrador/data/repositories/subscription_billing_repository.dart';
import 'package:mangopos_administrador/domain/models/card_charge_result.dart';
import 'package:mangopos_administrador/domain/models/subscription_billing.dart';
import 'package:mangopos_administrador/domain/models/invoice_payment_result.dart';
import 'package:mangopos_administrador/presentation/billing/widgets/mark_paid_dialog.dart';

class _FakeRepo extends BillingRepository {
  // Sin auto-refresh: GoTrue arranca un timer periódico que el test detecta
  // como pendiente al terminar. El repo falso nunca toca la red.
  _FakeRepo()
    : super(
        SupabaseClient(
          'http://localhost',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final calls = <({bool dryRun, String method, List<String> ids, Map<String, double> totals})>[];

  @override
  Future<InvoicePaymentResult> markInvoicesPaid({
    required List<String> invoiceIds,
    required String method,
    String? reference,
    DateTime? paidAt,
    bool dryRun = false,
    Map<String, double> totals = const {},
  }) async {
    calls.add((dryRun: dryRun, method: method, ids: invoiceIds, totals: totals));
    if (dryRun && invoiceIds.length > 1 && invoiceIds.every((id) => id.startsWith('m'))) {
      return InvoicePaymentResult.fromJson({'dry_run': true, 'paid': [
        for (final id in invoiceIds)
          {'invoice_id': id, 'invoice_number': id, 'business_id': 'b1', 'business_name': 'La Cocina Mexicana', 'total': 1500},
      ]});
    }
    return InvoicePaymentResult.fromJson({
      'dry_run': dryRun,
      'paid': [
        {'invoice_id': 'i1', 'invoice_number': 'MNG-2026-00041', 'business_id': 'b1',
         'business_name': 'Pollos El Sabor', 'total': 4799},
      ],
      'skipped': [
        {'invoice_id': 'i2', 'invoice_number': 'MNG-2026-00040', 'reason': 'paid'},
      ],
      'moved': [
        {'business_id': 'b1', 'business_name': 'Pollos El Sabor', 'invoice_number': 'MNG-2026-00041',
         'from': '2026-10-01', 'to': '2026-11-01', 'was_past_due': false},
      ],
    });
  }

  final cardCharges = <({List<String> ids, String key, Map<String, double> totals})>[];
  final verifies = <String>[];
  final cardResults = <CardChargeResult>[];
  final verifyResults = <CardChargeResult>[];

  @override
  Future<CardChargeResult> chargeInvoicesToCard({
    required List<String> invoiceIds,
    required String requestKey,
    Map<String, double> totals = const {},
  }) async {
    cardCharges.add((ids: invoiceIds, key: requestKey, totals: totals));
    return cardResults.removeAt(0);
  }

  @override
  Future<CardChargeResult> verifyCardCharge(String chargeId) async {
    verifies.add(chargeId);
    return verifyResults.removeAt(0);
  }
}

final _billing = SubscriptionBilling.fromJson({
  'membership_id': 'm-1',
  'business_id': 'b1',
  'billing_status': 'past_due',
  'card': {'status': 'verified', 'brand': 'mastercard', 'masked': '5438****1627', 'expiration': '202812'},
});

const _mexInvoices = [
  PayableInvoice(id: 'm1', number: 'MNG-2026-00051', businessId: 'b1', businessName: 'La Cocina Mexicana', total: 1500),
  PayableInvoice(id: 'm2', number: 'MNG-2026-00052', businessId: 'b1', businessName: 'La Cocina Mexicana', total: 1500),
];

Future<List<InvoicePaymentResult?>> _openCardDialog(
  WidgetTester tester,
  _FakeRepo repo, {
  List<PayableInvoice> invoices = _mexInvoices,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final returned = <InvoicePaymentResult?>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        billingRepositoryProvider.overrideWithValue(repo),
        subscriptionBillingProvider('b1').overrideWith((ref) async => _billing),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async => returned.add(await showDialog<InvoicePaymentResult>(
                  context: context,
                  builder: (_) => MarkPaidDialog(invoices: invoices),
                )),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cobrar a la tarjeta'));
  await tester.pumpAndSettle();
  return returned;
}

void main() {
  setUpAll(() => initializeDateFormatting('es_DO', null));

  testWidgets('vista previa del cobro corrido y pago real sin dry_run', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _FakeRepo();
    InvoicePaymentResult? returned;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [billingRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    returned = await showDialog<InvoicePaymentResult>(
                      context: context,
                      builder: (_) => const MarkPaidDialog(
                        invoices: [
                          PayableInvoice(id: 'i1', number: 'MNG-2026-00041', businessId: 'b1',
                              businessName: 'Pollos El Sabor', total: 4799),
                          PayableInvoice(id: 'i2', number: 'MNG-2026-00040', businessId: 'b1',
                              businessName: 'Pollos El Sabor', total: 4799),
                        ],
                      ),
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Vista previa pedida al abrir.
    expect(repo.calls.single.dryRun, isTrue);
    expect(find.text('Se corre el próximo cobro con tarjeta'), findsOneWidget);
    expect(find.textContaining('Pollos El Sabor · 1 oct → 1 nov'), findsOneWidget);
    expect(find.textContaining('ya estaba pagada'), findsOneWidget);
    // Solo 1 de las 2 se puede pagar: el botón lo dice.
    expect(find.text('Marcar como pagada'), findsOneWidget);

    await tester.tap(find.text('Efectivo'));
    await tester.pump();
    await tester.tap(find.text('Marcar como pagada'));
    await tester.pumpAndSettle();

    expect(repo.calls, hasLength(2));
    expect(repo.calls.last.dryRun, isFalse);
    expect(repo.calls.last.method, 'cash');
    expect(returned?.paid.single.invoiceId, 'i1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('se cobra solo lo marcado: desmarcar pide otra vista previa', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _FakeRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [billingRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showDialog<InvoicePaymentResult>(
                    context: context,
                    builder: (_) => const MarkPaidDialog(
                      invoices: [
                        PayableInvoice(id: 'i1', number: 'MNG-2026-00041', businessId: 'b1',
                            businessName: 'La Cocina Mexicana', total: 1500),
                        PayableInvoice(id: 'i2', number: 'MNG-2026-00042', businessId: 'b1',
                            businessName: 'La Cocina Mexicana', total: 1500),
                        PayableInvoice(id: 'i3', number: 'MNG-2026-00043', businessId: 'b1',
                            businessName: 'La Cocina Mexicana', total: 1500),
                      ],
                    ),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(repo.calls.single.ids, ['i1', 'i2', 'i3']);
    expect(find.text('Registrar pago de 3 facturas'), findsOneWidget);
    expect(find.text(formatRd(4500)), findsOneWidget);

    // Desmarcar la del medio: total y vista previa son de las otras dos.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Registrar pago de 2 facturas'), findsOneWidget);
    expect(find.text('Total (2 de 3)'), findsOneWidget);
    expect(find.text(formatRd(3000)), findsOneWidget);
    expect(repo.calls.last.ids, ['i1', 'i3']);
    expect(repo.calls.last.dryRun, isTrue);

    // Sin ninguna marcada no se puede confirmar.
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pumpAndSettle();
    expect(find.text('Marca al menos una factura.'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(find.ancestor(
      of: find.textContaining('Marcar'),
      matching: find.byType(FilledButton),
    ).last);
    expect(confirm.onPressed, isNull);
  });

  testWidgets('cobrar otro precio: va en la vista previa y en el pago', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _FakeRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [billingRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showDialog<InvoicePaymentResult>(
                    context: context,
                    builder: (_) => const MarkPaidDialog(
                      invoices: [
                        PayableInvoice(id: 'i1', number: 'MNG-2026-00041', businessId: 'b1',
                            businessName: 'La Cocina Mexicana', total: 1500),
                        PayableInvoice(id: 'i2', number: 'MNG-2026-00042', businessId: 'b1',
                            businessName: 'La Cocina Mexicana', total: 1500),
                      ],
                    ),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(repo.calls.single.totals, isEmpty);

    await tester.tap(find.byKey(const ValueKey('price-i2')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '1500.00'), '1,000');
    await tester.tap(find.text('Usar este precio'));
    await tester.pumpAndSettle();

    expect(find.text(formatRd(2500)), findsOneWidget); // 1,500 + 1,000
    expect(repo.calls.last.dryRun, isTrue);
    expect(repo.calls.last.totals, {'i2': 1000.0});

    await tester.tap(find.text('Marcar como pagada'));
    await tester.pumpAndSettle();
    expect(repo.calls.last.dryRun, isFalse);
    expect(repo.calls.last.totals, {'i2': 1000.0});
  });

  group('cobrar a la tarjeta', () {
    testWidgets('un cargo por el total, con confirmación', (tester) async {
      final repo = _FakeRepo()
        ..cardResults.add(CardChargeResult.fromJson({
          'status': 'approved',
          'charge_id': 'ch-1',
          'paid': [
            {'invoice_id': 'm1', 'invoice_number': 'MNG-2026-00051', 'business_id': 'b1', 'business_name': 'La Cocina Mexicana', 'total': 1500},
            {'invoice_id': 'm2', 'invoice_number': 'MNG-2026-00052', 'business_id': 'b1', 'business_name': 'La Cocina Mexicana', 'total': 1500},
          ],
        }));
      final returned = await _openCardDialog(tester, repo);

      expect(find.textContaining('MASTERCARD ••1627'), findsOneWidget);
      // Método, referencia y fecha son del pago registrado, no del cobro.
      expect(find.text('Efectivo'), findsNothing);
      await tester.tap(find.text('Cobrar ${formatRd(3000)}'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Es un cobro real'), findsOneWidget);
      expect(repo.cardCharges, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Cobrar'));
      await tester.pumpAndSettle();
      expect(repo.cardCharges.single.ids, ['m1', 'm2']);
      expect(repo.cardCharges.single.key, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(returned.single?.paid, hasLength(2));
    });

    testWidgets('sin respuesta clara: no deja volver a cobrar, solo verificar', (tester) async {
      final repo = _FakeRepo()
        ..cardResults.add(CardChargeResult.fromJson({
          'status': 'pending', 'charge_id': 'ch-2', 'message': 'No se supo si Azul cobró.',
        }))
        ..verifyResults.add(CardChargeResult.fromJson({'status': 'approved', 'charge_id': 'ch-2'}));
      final returned = await _openCardDialog(tester, repo);

      await tester.tap(find.text('Cobrar ${formatRd(3000)}'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cobrar'));
      await tester.pumpAndSettle();

      expect(find.text('No se supo si Azul cobró.'), findsOneWidget);
      expect(find.text('Cobrar ${formatRd(3000)}'), findsNothing);
      await tester.tap(find.text('Verificar cobro'));
      await tester.pumpAndSettle();
      expect(repo.verifies, ['ch-2']);
      expect(repo.cardCharges, hasLength(1));
      // Aprobado sin detalle: se informan las facturas que se cobraron.
      expect(returned.single?.paid.map((p) => p.invoiceId), ['m1', 'm2']);
    });

    testWidgets('rechazada: se informa y el reintento es otro pedido', (tester) async {
      final repo = _FakeRepo()
        ..cardResults.add(CardChargeResult.fromJson({
          'status': 'declined', 'charge_id': 'ch-3', 'message': 'Azul rechazó la tarjeta: FONDOS INSUFICIENTES.',
        }))
        ..cardResults.add(CardChargeResult.fromJson({'status': 'approved', 'charge_id': 'ch-4'}));
      await _openCardDialog(tester, repo);

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Cobrar ${formatRd(3000)}'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Cobrar'));
        await tester.pumpAndSettle();
        if (i == 0) expect(find.textContaining('FONDOS INSUFICIENTES'), findsOneWidget);
      }
      expect(repo.cardCharges, hasLength(2));
      expect(repo.cardCharges[0].key, isNot(repo.cardCharges[1].key));
    });

    testWidgets('facturas de dos negocios: no se ofrece cobrar a la tarjeta', (tester) async {
      final repo = _FakeRepo();
      await _openCardDialog(tester, repo, invoices: const [
        PayableInvoice(id: 'm1', number: 'A', businessId: 'b1', businessName: 'La Cocina Mexicana', total: 1500),
        PayableInvoice(id: 'm2', number: 'B', businessId: 'b2', businessName: 'Otro', total: 1500),
      ]);
      expect(find.text('Cobrar a la tarjeta es de un negocio a la vez.'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Cobrar ${formatRd(3000)}'));
      expect(confirm.onPressed, isNull);
    });
  });
}

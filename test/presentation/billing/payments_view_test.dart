// Pestaña Pagos de Facturación: totales, marcas de revisión y filtros.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mangopos_administrador/data/repositories/billing_repository.dart';
import 'package:mangopos_administrador/domain/models/payment_record.dart';
import 'package:mangopos_administrador/presentation/billing/widgets/payments_view.dart';

PaymentRecord _payment(Map<String, dynamic> json) => PaymentRecord.fromJson({
  'environment': 'production',
  'currency_code': 'DOP',
  'refunded_cents': 0,
  'sales_count': 1,
  ...json,
});

final _payments = [
  // La Maison, 16/08: Azul aprobó dos ventas por el mismo cobro.
  _payment({
    'kind': 'card',
    'id': 'c-maison-ago',
    'business_id': 'b-maison',
    'business_name': 'La Maison Francaise',
    'paid_at': '2026-08-16T07:00:10Z',
    'amount_cents': 299999,
    'method': 'card',
    'reference': '362377446',
    'period_start': '2026-08-16',
    'period_end': '2026-09-16',
    'invoice_id': 'i-1',
    'invoice_number': 'FAC-0101',
    'invoice_status': 'paid',
    'sales_count': 2,
    'card_label': 'MASTERCARD 5438****1627',
  }),
  // La Maison, 16/09: cobró lista con precio especial; se devolvió la diferencia.
  _payment({
    'kind': 'card',
    'id': 'c-maison-sep',
    'business_id': 'b-maison',
    'business_name': 'La Maison Francaise',
    'paid_at': '2026-09-16T07:00:07Z',
    'amount_cents': 479999,
    'method': 'card',
    'reference': '376998587',
    'period_start': '2026-09-16',
    'period_end': '2026-10-16',
    'invoice_id': 'i-2',
    'invoice_number': 'FAC-0102',
    'invoice_status': 'paid',
    'refunded_cents': 179999,
  }),
  // Tropella: transferencia registrada a mano.
  _payment({
    'kind': 'manual',
    'id': 'i-3',
    'business_id': 'b-tropella',
    'business_name': 'Tropella Coffee',
    'paid_at': '2026-09-05T15:00:00Z',
    'amount_cents': 299999,
    'method': 'transfer',
    'reference': 'TRX-889',
    'period_start': '2026-09-13',
    'period_end': '2026-10-12',
    'invoice_id': 'i-3',
    'invoice_number': 'FAC-0103',
    'invoice_status': 'paid',
    'sales_count': 0,
  }),
  // Car City: cobro con tarjeta que no dejó factura pagada.
  _payment({
    'kind': 'card',
    'id': 'c-carcity',
    'business_id': 'b-carcity',
    'business_name': 'Car City S.R.L',
    'paid_at': '2026-08-20T07:00:12Z',
    'amount_cents': 299999,
    'method': 'card',
    'reference': '363839492',
    'period_start': '2026-08-20',
    'period_end': '2026-09-20',
  }),
];

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1300, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [paymentsProvider.overrideWith((ref) async => _payments)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: PaymentsView(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('modelo', () {
    test('tarjeta: neto, duplicado y sin factura', () {
      final maisonAgo = _payments[0];
      expect(maisonAgo.isCard, isTrue);
      expect(maisonAgo.isDuplicated, isTrue);
      expect(maisonAgo.missingInvoice, isFalse);

      final maisonSep = _payments[1];
      expect(maisonSep.netCents, 300000);

      expect(_payments[3].missingInvoice, isTrue);
    });

    test('manual: nunca duplicado ni "sin factura"', () {
      final tropella = _payments[2];
      expect(tropella.kind, PaymentKind.manual);
      expect(tropella.methodLabel, 'Transferencia');
      expect(tropella.isDuplicated, isFalse);
      expect(tropella.missingInvoice, isFalse);
    });
  });

  group('filtros y totales', () {
    final now = DateTime(2026, 9, 17, 12);

    test(
      'totales: neto de reembolsos, tarjeta vs manual y lo que hay que revisar',
      () {
        final t = summarizePayments(_payments);
        expect(t.count, 4);
        expect(t.netCents, 299999 + 300000 + 299999 + 299999);
        expect(t.cardCents, 299999 + 300000 + 299999);
        expect(t.manualCents, 299999);
        expect(t.refundedCents, 179999);
        expect(t.duplicated, 1);
        expect(t.missingInvoice, 1);
      },
    );

    test('búsqueda por negocio, referencia o número de factura', () {
      List<String> ids(String q) => applyPaymentFilters(
        _payments,
        PaymentFilters(query: q),
        now: now,
      ).map((p) => p.id).toList();

      expect(ids('maison'), ['c-maison-ago', 'c-maison-sep']);
      expect(ids('TRX-889'), ['i-3']);
      expect(ids('fac-0102'), ['c-maison-sep']);
    });

    test('origen, negocio y período', () {
      expect(
        applyPaymentFilters(
          _payments,
          const PaymentFilters(source: PaymentSourceFilter.manual),
          now: now,
        ).single.id,
        'i-3',
      );
      expect(
        applyPaymentFilters(
          _payments,
          const PaymentFilters(businessId: 'b-carcity'),
          now: now,
        ).single.id,
        'c-carcity',
      );
      expect(
        applyPaymentFilters(
          _payments,
          const PaymentFilters(range: PaymentRangeFilter.thisMonth),
          now: now,
        ).map((p) => p.id),
        ['c-maison-sep', 'i-3'],
      );
      expect(
        applyPaymentFilters(
          _payments,
          const PaymentFilters(range: PaymentRangeFilter.last3Months),
          now: now,
        ),
        hasLength(4),
      );
    });
  });

  testWidgets('la pestaña muestra totales y marca lo que hay que revisar', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('RD\$ 11,999.97'), findsOneWidget);
    expect(find.text('4 pagos · RD\$ 1,799.99 reembolsado'), findsOneWidget);
    expect(find.text('1 cobrado 2 veces · 1 sin factura'), findsOneWidget);

    expect(find.text('COBRADO 2 VECES'), findsOneWidget);
    expect(find.text('Sin factura'), findsOneWidget);
    expect(find.text('Reembolsado RD\$ 1,799.99'), findsOneWidget);
    expect(find.text('Factura FAC-0103'), findsOneWidget);
    expect(find.text('TRX-889'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtrar por origen y por negocio', (tester) async {
    await _pump(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Manual'));
    await tester.pumpAndSettle();
    expect(find.text('Tropella Coffee'), findsOneWidget);
    expect(find.text('La Maison Francaise'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Todos'));
    await tester.pumpAndSettle();
    expect(find.text('La Maison Francaise'), findsNWidgets(2));

    // Tocar el nombre filtra a ese negocio; la X del chip lo quita.
    await tester.tap(find.text('Car City S.R.L'));
    await tester.pumpAndSettle();
    expect(find.text('Negocio: Car City S.R.L'), findsOneWidget);
    expect(find.text('La Maison Francaise'), findsNothing);
    expect(find.text('1 pagos'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('La Maison Francaise'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'tropella');
    await tester.pumpAndSettle();
    expect(find.text('Tropella Coffee'), findsOneWidget);
    expect(find.text('Car City S.R.L'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

// Pagos de suscripción y reembolsos: el operador ve el sobrecobro, el diálogo
// llena la diferencia, no deja pasar más de lo disponible y el reembolso sale
// con el monto exacto en centavos solo DESPUÉS de confirmar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mangopos_administrador/data/repositories/subscription_billing_repository.dart';
import 'package:mangopos_administrador/domain/models/subscription_charge.dart';
import 'package:mangopos_administrador/presentation/businesses/subscription_charges_section.dart';

class _FakeRepo extends SubscriptionBillingRepository {
  _FakeRepo({this.charges})
      : super(
          SupabaseClient(
            'http://localhost',
            'anon',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  /// Si viene, reemplaza la lista por defecto.
  final List<SubscriptionCharge>? charges;

  final refundCalls = <({String chargeId, int amountCents, String reason})>[];
  final verifyCalls = <String>[];

  @override
  Future<List<SubscriptionCharge>> listCharges(
    String businessId, {
    int limit = 24,
  }) async {
    final custom = charges;
    if (custom != null) return custom;
    return [
      // La Maison: cobró lista (4,799.99) con precio especial de 3,000 vigente.
      SubscriptionCharge.fromJson({
        'id': 'c-maison',
        'order_number': 'MP1234',
        'billing_period_start': '2026-09-16',
        'billing_period_end': '2026-10-16',
        'attempt_number': 1,
        'amount_cents': 479999,
        'status': 'approved',
        'azul_order_id': '376998587',
        'attempted_at': '2026-09-16T07:00:01Z',
        'card': {'brand': 'MASTERCARD', 'masked': '54386503****1627'},
        'current_price_cents': 300000,
        'refunded_cents': 0,
        'pending_refund_cents': 0,
        'refundable_cents': 479999,
        'refunds': [],
      }),
      // Cobro anterior con un reembolso sin confirmar.
      SubscriptionCharge.fromJson({
        'id': 'c-agosto',
        'order_number': 'MP1200',
        'billing_period_start': '2026-08-16',
        'billing_period_end': '2026-09-16',
        'attempt_number': 1,
        'amount_cents': 300000,
        'status': 'approved',
        'azul_order_id': '376000001',
        'attempted_at': '2026-08-16T07:00:01Z',
        'current_price_cents': 300000,
        'refunded_cents': 0,
        'pending_refund_cents': 50000,
        'refundable_cents': 250000,
        'refunds': [
          {
            'id': 'r-pend',
            'amount_cents': 50000,
            'status': 'pending',
            'reason': 'Prueba',
            'requested_by_email': 'ops@mangopos.do',
            'requested_at': '2026-09-17T12:00:00Z',
          },
        ],
      }),
    ];
  }

  @override
  Future<RefundActionResult> refundCharge({
    required String chargeId,
    required int amountCents,
    required String reason,
  }) async {
    refundCalls.add((chargeId: chargeId, amountCents: amountCents, reason: reason));
    return const RefundActionResult(
      approved: true,
      status: 'approved',
      message: 'Reembolso de RD\$1,799.99 aprobado por Azul.',
    );
  }

  @override
  Future<RefundActionResult> verifyRefund(String refundId) async {
    verifyCalls.add(refundId);
    return const RefundActionResult(
      approved: false,
      status: 'error',
      message: 'Azul no tiene registro de ese reembolso.',
    );
  }
}

Future<_FakeRepo> _pumpSection(WidgetTester tester, {_FakeRepo? withRepo}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = withRepo ?? _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [subscriptionBillingRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: SubscriptionChargesSection(
              businessId: 'b-maison',
              businessName: 'La Maison Francaise',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// La Maison Francaise, 16/08/2026: Azul aprobó DOS ventas en el mismo segundo
/// por un solo cobro. En azul_charges se veía un único cobro aprobado; las dos
/// ventas solo están en la bitácora (azul_sales, migración 0048).
SubscriptionCharge _duplicatedMaison({int refundedCents = 0}) {
  return SubscriptionCharge.fromJson({
    'id': 'c-dup',
    'order_number': 'MP2BD6142608161',
    'billing_period_start': '2026-08-16',
    'billing_period_end': '2026-09-16',
    'attempt_number': 1,
    'amount_cents': 299999,
    'status': 'approved',
    'azul_order_id': '362377446',
    'attempted_at': '2026-08-16T07:00:06Z',
    'current_price_cents': 299999,
    'refunded_cents': refundedCents,
    'pending_refund_cents': 0,
    'refundable_cents': 299999 - refundedCents,
    'refunds': [
      if (refundedCents > 0)
        {
          'id': 'r-dup',
          'amount_cents': refundedCents,
          'status': 'approved',
          'reason': 'Cobro duplicado',
          'requested_at': '2026-09-17T15:00:00Z',
        },
    ],
    'azul_sales': [
      {
        'azul_order_id': '362377445',
        'authorization_code': 'QI6N50',
        'approved_at': '2026-08-16T07:00:10Z',
      },
      {
        'azul_order_id': '362377446',
        'authorization_code': 'QJYZZS',
        'approved_at': '2026-08-16T07:00:10Z',
      },
    ],
  });
}

void main() {
  testWidgets('reembolso parcial de la diferencia con confirmación', (tester) async {
    final repo = await _pumpSection(tester);

    expect(find.text('Pagos de suscripción (2)'), findsOneWidget);
    expect(
      find.textContaining('Cobró RD\$ 1,799.99 más que el precio actual'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reembolsar').first);
    await tester.pumpAndSettle();

    // Atajo: diferencia con el precio especial.
    await tester.tap(find.text('Diferencia con precio actual · RD\$ 1,799.99'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '1799.99'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Ej: se cobró precio de lista con precio especial vigente'),
      'Cobró lista con precio especial vigente',
    );
    await tester.pump();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // Nada salió todavía: falta confirmar.
    expect(repo.refundCalls, isEmpty);
    expect(find.textContaining('Se devolverán RD\$ 1,799.99'), findsOneWidget);

    await tester.tap(find.text('Reembolsar RD\$ 1,799.99'));
    await tester.pumpAndSettle();

    expect(repo.refundCalls, hasLength(1));
    expect(repo.refundCalls.single.chargeId, 'c-maison');
    expect(repo.refundCalls.single.amountCents, 179999);
    expect(repo.refundCalls.single.reason, 'Cobró lista con precio especial vigente');
    expect(find.text('Reembolso de RD\$1,799.99 aprobado por Azul.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no deja continuar con más de lo disponible', (tester) async {
    final repo = await _pumpSection(tester);

    // El segundo cobro tiene 2,500.00 disponibles (500 sin confirmar).
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reembolsar').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin confirmar: RD\$ 500.00'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'RD\$ '), '2500.01');
    await tester.enterText(
      find.widgetWithText(TextField, 'Ej: se cobró precio de lista con precio especial vigente'),
      'Prueba',
    );
    await tester.pump();

    expect(find.text('Máximo RD\$ 2,500.00'), findsOneWidget);
    final continuar = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continuar'),
    );
    expect(continuar.onPressed, isNull);

    // Más de 2 decimales tampoco.
    await tester.enterText(find.widgetWithText(TextField, 'RD\$ '), '10.999');
    await tester.pump();
    expect(find.text('Monto inválido'), findsOneWidget);

    expect(repo.refundCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reembolso sin confirmar se verifica con Azul', (tester) async {
    final repo = await _pumpSection(tester);

    expect(find.text('SIN CONFIRMAR'), findsOneWidget);
    await tester.tap(find.text('Verificar con Azul'));
    await tester.pumpAndSettle();

    expect(repo.verifyCalls, ['r-pend']);
    expect(find.text('Azul no tiene registro de ese reembolso.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cobro duplicado: se ve en la consola y se devuelve la venta de más', (tester) async {
    final repo = await _pumpSection(
      tester,
      withRepo: _FakeRepo(charges: [_duplicatedMaison()]),
    );

    expect(find.text('1 COBRO DUPLICADO'), findsOneWidget);
    expect(find.text('COBRADO 2 VECES'), findsOneWidget);
    expect(
      find.textContaining('El cliente pagó RD\$ 5,999.98 en vez de RD\$ 2,999.99'),
      findsOneWidget,
    );
    expect(find.textContaining('Azul #362377445 · autorización QI6N50'), findsOneWidget);
    expect(find.textContaining('Azul #362377446 · autorización QJYZZS'), findsOneWidget);
    expect(find.text('Reembolsa RD\$ 2,999.99 para corregirlo.'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reembolsar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cobrado 2 veces en Azul'), findsOneWidget);

    // Atajo: monto de la venta de más + razón con los dos números de Azul.
    await tester.tap(find.text('Venta duplicada · RD\$ 2,999.99'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '2999.99'), findsOneWidget);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(repo.refundCalls, isEmpty);

    await tester.tap(find.text('Reembolsar RD\$ 2,999.99'));
    await tester.pumpAndSettle();

    expect(repo.refundCalls, hasLength(1));
    expect(repo.refundCalls.single.chargeId, 'c-dup');
    expect(repo.refundCalls.single.amountCents, 299999);
    expect(
      repo.refundCalls.single.reason,
      'Cobro duplicado: Azul aprobó 2 ventas por el mismo período '
      '(#362377445 y #362377446).',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicado ya devuelto: no dice REEMBOLSADO ni ofrece reembolsar', (tester) async {
    await _pumpSection(
      tester,
      withRepo: _FakeRepo(charges: [_duplicatedMaison(refundedCents: 299999)]),
    );

    expect(find.text('DUPLICADO DEVUELTO'), findsOneWidget);
    // El mes sigue pago con la otra venta: "REEMBOLSADO" sería falso.
    expect(find.text('REEMBOLSADO'), findsNothing);
    expect(find.text('1 COBRO DUPLICADO'), findsNothing);
    expect(find.textContaining('Lo cobrado de más ya se devolvió'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reembolsar'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

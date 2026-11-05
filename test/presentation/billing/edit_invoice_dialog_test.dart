// Editar una factura manda solo lo que cambió, y elegir la tarjeta de otro
// negocio del mismo dueño exige confirmar que el dueño lo autorizó.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mangopos_administrador/data/repositories/billing_repository.dart';
import 'package:mangopos_administrador/domain/models/membership_invoice.dart';
import 'package:mangopos_administrador/domain/models/subscription_billing.dart';
import 'package:mangopos_administrador/presentation/billing/widgets/edit_invoice_dialog.dart';
import 'package:mangopos_administrador/presentation/businesses/subscription_billing_section.dart';

class _FakeRepo extends BillingRepository {
  _FakeRepo()
    : super(
        SupabaseClient(
          'http://localhost',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final updates = <({String id, double? total, DateTime? dueDate, String? notes})>[];

  @override
  Future<void> updateInvoice(String invoiceId, {double? total, DateTime? dueDate, String? notes}) async {
    updates.add((id: invoiceId, total: total, dueDate: dueDate, notes: notes));
  }
}

final _invoice = MembershipInvoice.fromJson({
  'id': 'i1',
  'invoice_number': 'MNG-2026-00041',
  'business_id': 'b1',
  'business_name': 'La Cocina Mexicana',
  'plan_type': 'pro',
  'period_start': '2026-10-05',
  'period_end': '2026-11-04',
  'issue_date': '2026-10-01T12:00:00Z',
  'due_date': '2026-10-05T04:00:00Z',
  'amount': 1271.19,
  'itbis': 228.81,
  'total': 1500,
  'status': 'expired',
  'notes': 'Precio de lista.',
  'environment': 'production',
});

Future<void> _open(WidgetTester tester, Widget dialog, {List<Override> overrides = const []}) async {
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showDialog<Object?>(context: context, builder: (_) => dialog),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('es_DO', null));

  test('montos: la coma es de miles; el ITBIS incluido se separa como el servidor', () {
    expect(parseAmount('1,500.50'), 1500.5);
    expect(parseAmount(' 1000 '), 1000);
    expect(parseAmount(''), isNull);
    expect(parseAmount('abc'), isNull);
    // 1,500 con ITBIS: monto 1,271.19 + ITBIS 228.81.
    expect(itbisIncluded(1500), 228.81);
  });

  testWidgets('editar factura manda solo lo que cambió', (tester) async {
    final repo = _FakeRepo();
    await _open(
      tester,
      EditInvoiceDialog(invoice: _invoice),
      overrides: [billingRepositoryProvider.overrideWithValue(repo)],
    );

    expect(find.textContaining('Incluye ITBIS 18%'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '1500.00'), '1200');
    await tester.enterText(find.widgetWithText(TextField, 'Precio de lista.'), 'Acuerdo con el dueño.');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(repo.updates.single.id, 'i1');
    expect(repo.updates.single.total, 1200);
    expect(repo.updates.single.notes, 'Acuerdo con el dueño.');
    expect(repo.updates.single.dueDate, isNull);
  });

  testWidgets('sin cambios no llama al servidor', (tester) async {
    final repo = _FakeRepo();
    await _open(
      tester,
      EditInvoiceDialog(invoice: _invoice),
      overrides: [billingRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(repo.updates, isEmpty);
    expect(find.text('Guardar'), findsNothing);
  });

  testWidgets('tarjeta de otro negocio: sin la autorización del dueño no se usa', (tester) async {
    OwnerCardChoice? picked;
    const cards = [
      OwnerCard(paymentMethodId: 'pm1', businessId: 'b2', businessName: 'Cocina Mexicana Naco',
          brand: 'mastercard', masked: '5438****1627', expiration: '202812'),
      OwnerCard(paymentMethodId: 'pm2', businessId: 'b3', businessName: 'Cocina Mexicana Piantini',
          brand: 'visa', masked: '4111****1111', expiration: '202701', alreadyHere: true),
    ];
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async => picked = await showDialog<OwnerCardChoice>(
                context: context,
                builder: (_) => const OwnerCardDialog(businessName: 'La Cocina Mexicana', cards: cards),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('MASTERCARD ••1627 · vence 12/28'), findsOneWidget);
    expect(find.textContaining('este negocio ya la tiene'), findsOneWidget);
    FilledButton use() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Usar tarjeta'));
    expect(use().onPressed, isNull);

    await tester.tap(find.textContaining('El dueño autorizó'));
    await tester.pump();
    expect(use().onPressed, isNotNull);
    await tester.tap(find.text('Usar tarjeta'));
    await tester.pumpAndSettle();

    expect(picked?.card.paymentMethodId, 'pm1');
    expect(picked?.makeDefault, isTrue);
  });
}

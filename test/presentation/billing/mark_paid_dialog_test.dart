// El diálogo de pago muestra, ANTES de confirmar, qué cobros con tarjeta se
// corren — y el pago real sale sin dry_run. Es la garantía de que el operador
// no descubre el efecto sobre la tarjeta después.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mangopos_administrador/data/repositories/billing_repository.dart';
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

  final calls = <({bool dryRun, String method, List<String> ids})>[];

  @override
  Future<InvoicePaymentResult> markInvoicesPaid({
    required List<String> invoiceIds,
    required String method,
    String? reference,
    DateTime? paidAt,
    bool dryRun = false,
  }) async {
    calls.add((dryRun: dryRun, method: method, ids: invoiceIds));
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
}

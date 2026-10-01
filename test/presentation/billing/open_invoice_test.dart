// Abrir una factura desde la matriz: si no se puede, el "Abriendo factura…"
// se cierra y el operador ve por qué — nunca queda un diálogo colgado.
// (El PDF y el preview nativo no se prueban acá: necesitan red y plugin.)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mangopos_administrador/data/repositories/billing_repository.dart';
import 'package:mangopos_administrador/domain/models/membership_invoice.dart';
import 'package:mangopos_administrador/presentation/billing/widgets/open_invoice.dart';

class _FakeRepo extends BillingRepository {
  _FakeRepo({this.fail = false})
      : super(
          SupabaseClient(
            'http://localhost',
            'anon',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final bool fail;
  final asked = <String>[];

  @override
  Future<List<MembershipInvoice>> forBusiness(String businessId) async {
    asked.add(businessId);
    if (fail) throw Exception('sin conexión');
    return const [];
  }
}

Future<void> _pumpAndTap(WidgetTester tester, _FakeRepo repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [billingRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => openInvoicePdfById(
                  context,
                  businessId: 'b-maison',
                  invoiceId: 'inv-no-existe',
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
}

void main() {
  testWidgets('factura que no está: cierra el cargando y lo dice', (tester) async {
    final repo = _FakeRepo();
    await _pumpAndTap(tester, repo);

    expect(repo.asked, ['b-maison']);
    expect(find.text('Abriendo factura…'), findsNothing);
    expect(find.text('No se encontró la factura.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error del servidor: cierra el cargando y muestra el error', (tester) async {
    await _pumpAndTap(tester, _FakeRepo(fail: true));

    expect(find.text('Abriendo factura…'), findsNothing);
    expect(find.textContaining('No se pudo abrir la factura'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

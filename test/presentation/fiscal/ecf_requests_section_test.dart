// Bandeja de solicitudes de facturación electrónica en la página Fiscal.
// Lo que protege: que las solicitudes ya activas no ensucien la bandeja y que
// sin pendientes la sección no ocupe espacio.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mangopos_administrador/data/repositories/ecf_onboarding_repository.dart';
import 'package:mangopos_administrador/domain/models/ecf_onboarding.dart';
import 'package:mangopos_administrador/presentation/fiscal/ecf_requests_section.dart';

Future<void> _pump(WidgetTester tester, List<EcfRequestSummary> requests) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ecfRequestsProvider.overrideWith((ref) async => requests)],
      child: const MaterialApp(home: Scaffold(body: EcfRequestsSection())),
    ),
  );
  await tester.pumpAndSettle();
}

EcfRequestSummary _req(String id, String stage) => EcfRequestSummary.fromJson({
      'business_id': id,
      'business_name': 'Negocio $id',
      'stage': stage,
      'requested_at': '2026-09-17T15:00:00Z',
    });

void main() {
  setUpAll(() => initializeDateFormatting('es', null));

  testWidgets('muestra pendientes y oculta las activas', (tester) async {
    await _pump(tester, [_req('a', 'company'), _req('b', 'active'), _req('c', 'sequences')]);
    expect(find.textContaining('(2)'), findsOneWidget);
    expect(find.text('Negocio a'), findsOneWidget);
    expect(find.text('Negocio b'), findsNothing);
    expect(find.text('Faltan secuencias'), findsOneWidget);
  });

  testWidgets('sin pendientes no pinta nada', (tester) async {
    await _pump(tester, [_req('b', 'active')]);
    expect(find.textContaining('SOLICITUDES'), findsNothing);
  });
}

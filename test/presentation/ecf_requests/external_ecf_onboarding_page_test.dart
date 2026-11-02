// Página de alta e-CF de una empresa de Busi Pos Web. Lo que protege: que
// abra el alta del dueño correcto (la solicitud, no un negocio) y que el
// seguimiento siga a un botón.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mangopos_administrador/data/repositories/ecf_onboarding_repository.dart';
import 'package:mangopos_administrador/data/repositories/external_ecf_requests_repository.dart';
import 'package:mangopos_administrador/domain/models/ecf_onboarding.dart';
import 'package:mangopos_administrador/domain/models/external_ecf_request.dart';
import 'package:mangopos_administrador/presentation/ecf_requests/external_ecf_onboarding_page.dart';

const _request = {
  'id': 'x1',
  'source': 'flutter_shop+',
  'external_id': 'c-1',
  'status': 'in_progress',
  'company_name': 'Maranatha',
  'rnc': '131831151',
  'alanube_company_id': '01EXT',
  'company_registered': true,
};

void main() {
  setUpAll(() => initializeDateFormatting('es', null));

  testWidgets('abre el alta de la solicitud y el seguimiento a un botón', (tester) async {
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final asked = <EcfOwner>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        externalEcfRequestsProvider.overrideWith((ref) async => [ExternalEcfRequest.fromJson(_request)]),
        ecfOnboardingStatusProvider.overrideWith((ref, owner) async {
          asked.add(owner);
          return EcfOnboardingStatus.fromJson({
            'business': null,
            'external_request': _request,
            'onboarding': null,
            'sequences': const [],
            'environment': 'production',
          });
        }),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ExternalEcfOnboardingPage(requestId: 'x1'))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(asked, [const EcfOwner.external('x1')]);
    expect(find.text('Maranatha'), findsOneWidget);
    expect(find.textContaining('Empresa (id allá) c-1'), findsOneWidget);
    expect(find.text('Datos del contribuyente'), findsOneWidget);

    await tester.tap(find.text('Datos y seguimiento'));
    await tester.pumpAndSettle();
    expect(find.text('SEGUIMIENTO'), findsOneWidget);
  });
}

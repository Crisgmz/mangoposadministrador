// La sección de alta e-CF se dibuja en cada estado sin romperse, y "Activar"
// solo se habilita después de una verificación sin puntos en rojo — la
// garantía de que el operador no activa a ciegas.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mangopos_administrador/data/repositories/ecf_onboarding_repository.dart';
import 'package:mangopos_administrador/domain/models/ecf_onboarding.dart';
import 'package:mangopos_administrador/presentation/businesses/ecf_onboarding_section.dart';

class _FakeRepo extends EcfOnboardingRepository {
  _FakeRepo(this.checks)
    : super(
        SupabaseClient(
          'http://localhost',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final List<Map<String, dynamic>> checks;
  final provisions = <bool>[];

  @override
  Future<EcfPreflightResult> provision({
    required String businessId,
    required String alanubeCompanyId,
    required bool dryRun,
  }) async {
    provisions.add(dryRun);
    return EcfPreflightResult.fromJson({'wrote': !dryRun, 'checks': checks});
  }
}

Map<String, dynamic> _json({
  Map<String, dynamic>? onboarding,
  Map<String, dynamic>? fiscal,
  List<Map<String, dynamic>> sequences = const [],
  Map<String, dynamic>? settings,
  Map<String, dynamic>? company,
}) =>
    {
      'business': {'id': 'b1', 'business_name': 'Tropella Coffee', 'address': 'Real Food Park'},
      'onboarding': onboarding,
      'fiscal': fiscal,
      'fiscal_sync': onboarding == null ? null : {'rnc_matches': false, 'legal_name_matches': true},
      'sequences': sequences,
      'alanube_settings': settings,
      'company': company,
      'company_error': null,
      'environment': 'production',
    };

Future<_FakeRepo> _pump(
  WidgetTester tester,
  Map<String, dynamic> status, {
  List<Map<String, dynamic>> checks = const [],
  double width = 1100,
}) async {
  tester.view.physicalSize = Size(width, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = _FakeRepo(checks);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ecfOnboardingRepositoryProvider.overrideWithValue(repo),
        ecfOnboardingStatusProvider('b1').overrideWith(
          (ref) async => EcfOnboardingStatus.fromJson(status),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EcfOnboardingSection(businessId: 'b1'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUpAll(() => initializeDateFormatting('es', null));

  testWidgets('negocio nuevo: pide capturar datos y no deja dar de alta', (tester) async {
    await _pump(tester, _json(fiscal: {'rnc': '133328828', 'business_legal_name': 'TROPELLA', 'ecf_enabled': false}));

    expect(find.text('Capturar datos'), findsOneWidget);
    expect(find.textContaining('La POS tiene RNC 133328828'), findsOneWidget);
    final alta = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Dar de alta con certificado'), matching: find.byWidgetPredicate((w) => w is FilledButton)),
    );
    expect(alta.onPressed, isNull);
    // Certificación y activación esperan a la empresa.
    expect(find.text('Primero vincula o da de alta la empresa en Alanube.'), findsNWidgets(2));
  });

  testWidgets('datos distintos a la POS: ofrece copiarlos', (tester) async {
    await _pump(
      tester,
      _json(
        onboarding: {
          'rnc': '133328828',
          'legal_name': 'TROPELLA COFFEE SRL',
          'fiscal_address': 'GREGORIO LUPERON, No. B 4, GURABO',
        },
        fiscal: {'rnc': '999999999', 'business_legal_name': 'TROPELLA COFFEE SRL'},
      ),
    );

    expect(find.text('Copiar a la POS'), findsOneWidget);
    expect(find.text('Dirección del local'), findsOneWidget);
  });

  testWidgets('Activar se habilita solo tras verificar sin rojo', (tester) async {
    final repo = await _pump(
      tester,
      _json(
        onboarding: {
          'rnc': '133328828',
          'legal_name': 'TROPELLA COFFEE SRL',
          'fiscal_address': 'GURABO',
          'alanube_company_id': '01M11V7B6J4X6FQ5SRAFPVPATV',
          'company_linked_via': 'existing',
        },
        fiscal: {'rnc': '133328828', 'business_legal_name': 'TROPELLA COFFEE SRL', 'ecf_enabled': false},
        sequences: [
          {'id': 's1', 'ncf_type': 'E31', 'range_start': 1, 'range_end': 100, 'current_number': 2, 'is_active': true},
          {'id': 's2', 'ncf_type': 'E32', 'range_start': 1, 'range_end': 1000, 'current_number': 3, 'is_active': true},
        ],
        company: {
          'id': '01M11V7B6J4X6FQ5SRAFPVPATV',
          'name': 'TROPELLA COFFEE SRL',
          'identification': '133328828',
          'certification_step': 2,
          'webhooks_ok': true,
          'certificate': {'name': 'FIRMA DIGITAL', 'end_date': '2027-04-23 21:30:54'},
        },
      ),
      checks: [
        {'key': 'rnc', 'level': 'ok', 'message': 'RNC 133328828 coincide.'},
        {'key': 'address', 'level': 'warn', 'message': 'La direccion difiere.'},
      ],
    );

    // E31 sin vencimiento: la sección lo marca.
    expect(find.textContaining('FALTA vencimiento'), findsOneWidget);
    expect(find.textContaining('Sin E34'), findsOneWidget);

    FilledButton activar() => tester.widget<FilledButton>(
          find.ancestor(of: find.text('Activar'), matching: find.byWidgetPredicate((w) => w is FilledButton)),
        );
    expect(activar().onPressed, isNull);

    await tester.tap(find.text('Verificar'));
    await tester.pumpAndSettle();

    expect(repo.provisions, [true]);
    expect(find.text('La direccion difiere.'), findsOneWidget);
    expect(activar().onPressed, isNotNull);
  });

  testWidgets('verificación con rojo mantiene Activar apagado', (tester) async {
    await _pump(
      tester,
      _json(
        onboarding: {'rnc': '133328828', 'legal_name': 'X', 'fiscal_address': 'Y', 'alanube_company_id': '01M1'},
        sequences: [
          {'id': 's2', 'ncf_type': 'E32', 'range_start': 1, 'range_end': 1000, 'current_number': 0, 'is_active': true},
        ],
      ),
      checks: [
        {'key': 'certificate', 'level': 'fail', 'message': 'Sin certificado.'},
      ],
    );

    await tester.tap(find.text('Verificar'));
    await tester.pumpAndSettle();

    final activar = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Activar'), matching: find.byWidgetPredicate((w) => w is FilledButton)),
    );
    expect(activar.onPressed, isNull);
    expect(find.textContaining('Hay puntos en rojo'), findsOneWidget);
  });

  testWidgets('activado: aparece el switch de modalidad', (tester) async {
    await _pump(
      tester,
      _json(
        fiscal: {'rnc': '133328828', 'ecf_enabled': true, 'default_ncf_type': 'E32'},
        sequences: [
          {'id': 's2', 'ncf_type': 'E32', 'range_start': 1, 'range_end': 1000, 'current_number': 3, 'is_active': true},
        ],
        settings: {'alanube_company_id': '01M11V7B6J4X6FQ5SRAFPVPATV', 'environment': 'production', 'mode': 'hybrid'},
      ),
    );

    expect(find.text('Este negocio ya emite comprobantes electrónicos.'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('Activar'), findsNothing);
  });

  testWidgets('certificación en curso: subpasos, set rechazado y botón de reintento', (tester) async {
    await _pump(
      tester,
      {
        ..._json(
          onboarding: {
            'rnc': '133328828',
            'legal_name': 'NUEVO CLIENTE SRL',
            'fiscal_address': 'SANTIAGO',
            'alanube_company_id': '01M1',
            'postulation_signed_at': '2026-09-17T15:00:00Z',
            'set_test_id': '01X',
          },
        ),
        'set_test': {
          'id': '01X',
          'status': 'REJECTED',
          'retry_number': 2,
          'processed': 20,
          'documents': [
            {'type': 'creditNote', 'status': 'REJECTED', 'encf': 'E340000001820'},
          ],
        },
      },
    );

    expect(find.text('Certificación DGII'), findsOneWidget);
    expect(find.text('Firmar XML de postulación'), findsOneWidget);
    expect(find.textContaining('Firmado el'), findsOneWidget);
    expect(find.textContaining('rechazados: E340000001820'), findsOneWidget);
    expect(find.text('Generar de nuevo'), findsOneWidget);
    expect(find.text('Consultar'), findsNothing);
    expect(find.text('La DGII ya lo autorizó'), findsOneWidget);
    // Sin autorización, el paso de secuencias sigue disponible pero no es el actual.
    expect(find.text('Cargar secuencia'), findsOneWidget);
  });

  testWidgets('set aceptado ofrece descargar documentos y resúmenes', (tester) async {
    await _pump(
      tester,
      {
        ..._json(
          onboarding: {
            'rnc': '133328828',
            'legal_name': 'NUEVO CLIENTE SRL',
            'fiscal_address': 'SANTIAGO',
            'alanube_company_id': '01M1',
            'set_test_id': '01X',
          },
        ),
        'set_test': {
          'id': '01X',
          'status': 'ACCEPTED',
          'processed': 20,
          'documents_zip_url': 'https://s3/docs.zip',
          'resumes_zip_url': 'https://s3/res.zip',
        },
      },
    );

    expect(find.text('Documentos'), findsOneWidget);
    expect(find.text('Resúmenes'), findsOneWidget);
    expect(find.text('Generar'), findsNothing);
  });

  testWidgets('cliente ya autorizado: la certificación queda resumida', (tester) async {
    await _pump(
      tester,
      _json(
        onboarding: {
          'rnc': '133328828',
          'legal_name': 'TROPELLA COFFEE SRL',
          'fiscal_address': 'GURABO',
          'alanube_company_id': '01M1',
        },
        sequences: [
          {'id': 's2', 'ncf_type': 'E32', 'range_start': 1, 'range_end': 1000, 'current_number': 3, 'is_active': true},
        ],
      ),
    );

    expect(find.textContaining('ya tiene secuencias electrónicas'), findsOneWidget);
    expect(find.text('Firmar XML de postulación'), findsNothing);
  });

  testWidgets('certificación en pantalla angosta no desborda', (tester) async {
    await _pump(
      tester,
      {
        ..._json(
          onboarding: {
            'rnc': '133328828',
            'legal_name': 'NUEVO CLIENTE SRL',
            'fiscal_address': 'SANTIAGO',
            'alanube_company_id': '01M1',
            'set_test_id': '01X',
          },
        ),
        'set_test': {
          'id': '01X',
          'status': 'ACCEPTED',
          'processed': 20,
          'documents_zip_url': 'https://s3/docs.zip',
          'resumes_zip_url': 'https://s3/res.zip',
        },
      },
      width: 480,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Resúmenes'), findsOneWidget);
  });
}

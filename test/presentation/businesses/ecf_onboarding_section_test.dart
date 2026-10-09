// La sección de alta e-CF se dibuja en cada estado sin romperse, y "Activar"
// solo se habilita después de una verificación sin puntos en rojo — la
// garantía de que el operador no activa a ciegas.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
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

const _certifying = {
  'rnc': '133051842',
  'legal_name': 'NUEVO CLIENTE SRL',
  'fiscal_address': 'SANTIAGO',
  'alanube_company_id': '01M1',
};

Map<String, dynamic> _case(
  String encf,
  String status, {
  String via = 'ecf',
  num? total,
  String? modifies,
  List<Map<String, dynamic>> messages = const [],
}) =>
    {
      'id': 'c-$encf',
      'position': 1,
      'case_id': '133051842$encf',
      'ecf_type': encf.substring(1, 3),
      'encf': encf,
      'total': total,
      'via': via,
      'modifies': modifies,
      'status': status,
      'messages': messages,
    };

Map<String, dynamic> _testSet(List<Map<String, dynamic>> cases) => {
      'filename': '133051842-08102026121048.xlsx',
      'loaded_at': '2026-10-08T16:10:48Z',
      'session_expires_at': null,
      'cases': cases,
    };

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

  testWidgets('certificación sin set: pide cargar el archivo de la DGII', (tester) async {
    await _pump(
      tester,
      _json(onboarding: {..._certifying, 'postulation_signed_at': '2026-09-17T15:00:00Z'}),
    );

    expect(find.text('Certificación DGII'), findsOneWidget);
    expect(find.text('Firmar XML de postulación'), findsOneWidget);
    expect(find.textContaining('Firmado el'), findsOneWidget);
    expect(find.text('Pruebas de datos e-CF'), findsOneWidget);
    expect(find.textContaining('(Pruebas de datos e-CF) un Excel'), findsOneWidget);
    expect(find.text('Pruebas de aprobación comercial'), findsOneWidget);
    // Un "Cargar archivo" por cada set de la DGII.
    expect(find.text('Cargar archivo'), findsNWidgets(2));
    expect(find.text('Enviar a la DGII'), findsNothing);
    expect(find.text('La DGII ya lo autorizó'), findsOneWidget);
    // Sin autorización, el paso de secuencias sigue disponible pero no es el actual.
    expect(find.text('Cargar secuencia'), findsOneWidget);
  });

  testWidgets('set cargado: enviar, consultar y ver comprobantes', (tester) async {
    await _pump(tester, {
      ..._json(onboarding: _certifying),
      'test_set': _testSet([
        _case('E310000000001', 'accepted', total: 1180),
        _case('E320000000011', 'sent', via: 'rfce', total: 40120),
        _case('E340000000001', 'pending', modifies: 'E310000000001'),
      ]),
    });

    expect(find.textContaining('3 comprobantes (1 de consumo van como resumen) · 1 aceptados'), findsOneWidget);
    expect(find.text('Continuar envío'), findsOneWidget);
    expect(find.text('Consultar'), findsOneWidget);
    expect(find.text('Cargar otro'), findsOneWidget);

    await tester.tap(find.text('Ver comprobantes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('E340000000001 · Nota de crédito'), findsOneWidget);
    expect(find.textContaining('modifica E310000000001'), findsOneWidget);
    expect(find.textContaining('Facturas de consumo < 250Mil'), findsOneWidget);
    // Lo pendiente todavía no tiene XML firmado.
    final downloads = tester.widgetList<IconButton>(find.widgetWithIcon(IconButton, HugeIcons.strokeRoundedDownload04));
    expect(downloads.map((b) => b.onPressed != null), [true, true, false]);
  });

  testWidgets('aprobaciones comerciales: su propio paso, sin tocar el set de e-CF', (tester) async {
    await _pump(tester, {
      ..._json(onboarding: _certifying),
      'test_set': _testSet([
        _case('E310000000001', 'accepted'),
      ]),
      'approval_set': {
        ..._testSet([
          _case('E310000000001', 'accepted', via: 'acecf', total: 7080),
          _case('E340000000018', 'pending', via: 'acecf', total: 0),
          _case('E450000000002', 'error', via: 'acecf', messages: [
            {'code': null, 'message': 'El e-NCF no existe'},
          ]),
        ]),
        'kind': 'acecf',
        'filename': '133051842-09102026121152.xlsx',
      },
    });

    expect(find.textContaining('3 aprobaciones · 1 aceptadas · 2 por enviar.'), findsOneWidget);
    expect(find.textContaining('No se pudieron enviar E450000000002'), findsOneWidget);
    // El e-CF ya está completo: solo el paso de aprobaciones ofrece enviar.
    expect(find.text('Continuar envío'), findsOneWidget);
    expect(find.text('Consultar'), findsNothing);

    await tester.tap(find.text('Ver aprobaciones'));
    await tester.pumpAndSettle();
    expect(find.text('133051842-09102026121152.xlsx'), findsOneWidget);
    expect(find.textContaining('E340000000018 · Nota de crédito'), findsOneWidget);
    expect(find.text('El e-NCF no existe'), findsOneWidget);
    // Sin resúmenes de consumo, no aparece la nota del portal.
    expect(find.textContaining('Facturas de consumo < 250Mil'), findsNothing);
  });

  testWidgets('simulación: sin el set de datos no se puede generar', (tester) async {
    await _pump(tester, _json(onboarding: _certifying));

    expect(find.text('Pruebas de simulación e-CF'), findsOneWidget);
    expect(find.textContaining('cárgalo primero'), findsOneWidget);
    final generate = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('Generar comprobantes'), matching: find.byType(OutlinedButton)),
    );
    expect(generate.onPressed, isNull);
  });

  testWidgets('simulación generada: enviar, ver, PDFs y generar de nuevo', (tester) async {
    await _pump(tester, {
      ..._json(onboarding: _certifying),
      'test_set': _testSet([_case('E310000000001', 'accepted')]),
      'simulation_set': {
        ..._testSet([
          _case('E310000000013', 'accepted', total: 7080),
          _case('E320000000017', 'accepted', via: 'rfce', total: 40120),
          _case('E340000000020', 'pending', modifies: 'E310000000013'),
        ]),
        'kind': 'sim',
        'filename': null,
      },
    });

    expect(find.textContaining('3 comprobantes (1 de consumo van como resumen) · 2 aceptados · 1 por enviar.'), findsOneWidget);
    expect(find.text('Representaciones (PDF)'), findsOneWidget);
    expect(find.text('Generar de nuevo'), findsOneWidget);
    // El set de datos ya está aceptado: el único "Continuar envío" es el de la simulación.
    expect(find.text('Continuar envío'), findsOneWidget);

    await tester.tap(find.text('Ver comprobantes').last);
    await tester.pumpAndSettle();
    expect(find.text('Simulación e-CF'), findsOneWidget);
    // XML y PDF para lo firmado; lo pendiente todavía no tiene ninguno.
    final pdfs = tester.widgetList<IconButton>(find.widgetWithIcon(IconButton, HugeIcons.strokeRoundedPdf01));
    expect(pdfs.map((b) => b.onPressed != null), [true, true, false]);
  });

  testWidgets('set rechazado: no deja enviar y pide cargar el nuevo', (tester) async {
    await _pump(tester, {
      ..._json(onboarding: _certifying),
      'test_set': _testSet([
        _case('E310000000001', 'rejected', messages: [
          {'code': '2', 'message': 'Rechazado por la DGII'},
        ]),
        _case('E340000000001', 'pending'),
      ]),
    });

    expect(find.textContaining('La DGII rechazó E310000000001'), findsOneWidget);
    expect(find.text('Enviar a la DGII'), findsNothing);
    expect(find.text('Continuar envío'), findsNothing);
    expect(find.text('Cargar otro'), findsOneWidget);
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
        ..._json(onboarding: _certifying),
        'test_set': _testSet([
          _case('E310000000001', 'accepted'),
          _case('E320000000011', 'sent', via: 'rfce'),
          _case('E340000000001', 'error', messages: [
            {'code': null, 'message': 'La DGII no respondio a tiempo al enviar el e-CF.'},
          ]),
        ]),
      },
      width: 480,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Ver comprobantes'), findsOneWidget);
  });
}

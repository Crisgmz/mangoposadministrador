// La sección de alta e-CF se dibuja en cada estado sin romperse, y "Activar"
// solo se habilita después de una verificación sin puntos en rojo — la
// garantía de que el operador no activa a ciegas.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mangopos_administrador/data/repositories/ecf_onboarding_repository.dart';
import 'package:mangopos_administrador/domain/models/ecf_onboarding.dart';
import 'package:mangopos_administrador/presentation/businesses/ecf_onboarding_dialogs.dart';
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
  final simulationCounts = <Map<String, int>>[];
  final ofvReveals = <String>[];
  Object? ofvError;
  Completer<EcfOfvCredentials>? ofvResponse;
  final registrations = <Map<String, dynamic>>[];
  final certificateSaves = <Map<String, dynamic>>[];
  final testSetSends = <Map<String, dynamic>>[];
  Object? certificateSaveError;

  @override
  Future<EcfCompany?> registerCompany({
    required EcfOwner owner,
    String? certificateFilename,
    Uint8List? certificateBytes,
    String? certificatePassword,
  }) async {
    registrations.add({
      'business_id': owner.id,
      'filename': certificateFilename,
      'bytes': certificateBytes,
      'password': certificatePassword,
    });
    return null;
  }

  @override
  Future<void> saveCertificate({
    required EcfOwner owner,
    required String certificateFilename,
    required Uint8List certificateBytes,
    required String certificatePassword,
    bool clientAuthorizedStorage = false,
  }) async {
    if (certificateSaveError != null) throw certificateSaveError!;
    certificateSaves.add({
      'business_id': owner.id,
      'owner': owner,
      'authorized': clientAuthorizedStorage,
      'filename': certificateFilename,
      'bytes': certificateBytes,
      'password': certificatePassword,
    });
  }

  @override
  Future<EcfTestSetSendResult> sendTestSet({
    required EcfOwner owner,
    required String setKind,
    String? certificateFilename,
    Uint8List? certificateBytes,
    String? certificatePassword,
  }) async {
    testSetSends.add({
      'business_id': owner.id,
      'set_kind': setKind,
      'filename': certificateFilename,
      'bytes': certificateBytes,
      'password': certificatePassword,
    });
    return EcfTestSetSendResult(
      sent: 1,
      more: false,
      testSet: EcfTestSet(cases: const [], kind: setKind),
    );
  }

  @override
  Future<EcfOfvCredentials> revealOfvPassword(EcfOwner owner) async {
    ofvReveals.add(owner.id);
    if (ofvError != null) throw ofvError!;
    if (ofvResponse != null) return ofvResponse!.future;
    return const EcfOfvCredentials(ofvUser: 'usuario.prueba', ofvPassword: '  Clave de prueba #2026  ');
  }

  @override
  Future<EcfTestSet> generateSimulationSet(EcfOwner owner, {required Map<String, int> counts}) async {
    simulationCounts.add(counts);
    return const EcfTestSet(cases: [], kind: 'sim');
  }

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
  Map<String, dynamic>? external,
}) =>
    {
      'business': external != null
          ? null
          : {'id': 'b1', 'business_name': 'Tropella Coffee', 'address': 'Real Food Park'},
      'external_request': external,
      'onboarding': onboarding,
      'fiscal': fiscal,
      'fiscal_sync': onboarding == null || external != null
          ? null
          : {'rnc_matches': false, 'legal_name_matches': true},
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
  EcfOwner owner = const EcfOwner.business('b1'),
}) async {
  tester.view.physicalSize = Size(width, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = _FakeRepo(checks);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ecfOnboardingRepositoryProvider.overrideWithValue(repo),
        ecfOnboardingStatusProvider(owner).overrideWith(
          (ref) async => EcfOnboardingStatus.fromJson(status),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EcfOnboardingSection(owner: owner),
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

const _requestedWithOfv = {
  ..._certifying,
  'requested_at': '2026-10-27T15:00:00Z',
  'ofv_user': 'usuario.prueba',
  'ofv_password_updated_at': '2026-10-27T15:00:00Z',
};

const _requestedWithCertificate = {
  ..._certifying,
  'requested_at': '2026-10-27T15:00:00Z',
  'certificate_filename': 'cliente-prueba.p12',
  'certificate_updated_at': '2026-10-27T15:00:00Z',
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

  testWidgets('alta prefiere certificado recibido sin volver a pedir el archivo o la clave', (tester) async {
    final repo = await _pump(tester, _json(onboarding: {
      ..._requestedWithCertificate,
      'alanube_company_id': null,
    }), width: 480);
    expect(find.text('cliente-prueba.p12'), findsOneWidget);
    expect(find.text('Reemplazar certificado'), findsOneWidget);

    await tester.tap(find.text('Dar de alta con certificado'));
    await tester.pumpAndSettle();
    expect(find.text('Usar certificado de la solicitud'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Contraseña del certificado'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Dar de alta'));
    await tester.pumpAndSettle();

    expect(repo.registrations, [{
      'business_id': 'b1', 'filename': null, 'bytes': null, 'password': null,
    }]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('elegir otro certificado vuelve a pedir archivo y contraseña', (tester) async {
    await _pump(tester, _json(onboarding: {
      ..._requestedWithCertificate,
      'alanube_company_id': null,
    }));
    await tester.tap(find.text('Dar de alta con certificado'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subir otro certificado').last);
    await tester.pumpAndSettle();

    expect(find.text('Elegir certificado (.p12)'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Contraseña del certificado'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Dar de alta')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('alta sin certificado recibido mantiene la subida manual', (tester) async {
    await _pump(tester, _json(onboarding: {
      ..._certifying,
      'alanube_company_id': null,
    }));
    expect(find.text('No recibido'), findsOneWidget);
    expect(find.text('Cargar certificado'), findsOneWidget);
    await tester.tap(find.text('Dar de alta con certificado'));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<bool>), findsNothing);
    expect(find.text('Elegir certificado (.p12)'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Dar de alta')).onPressed, isNull);
  });

  for (final entry in {'ecf': 'test_set', 'acecf': 'approval_set', 'sim': 'simulation_set'}.entries) {
    testWidgets('${entry.key}: firma con el certificado recibido sin reenviar bytes o contraseña', (tester) async {
      final repo = await _pump(tester, {
        ..._json(onboarding: _requestedWithCertificate),
        entry.value: {
          ..._testSet([_case('E310000000001', 'pending')]),
          'kind': entry.key,
        },
      });
      await tester.tap(find.text('Enviar a la DGII'));
      await tester.pumpAndSettle();
      expect(find.text('Usar certificado de la solicitud'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Contraseña del certificado'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Firmar y enviar'));
      await tester.pumpAndSettle();

      expect(repo.testSetSends, [{
        'business_id': 'b1', 'set_kind': entry.key,
        'filename': null, 'bytes': null, 'password': null,
      }]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('negocio anterior puede guardar certificado sin crear otra empresa', (tester) async {
    final repo = await _pump(tester, _json(
      onboarding: _certifying,
      fiscal: {'ecf_enabled': true},
      settings: {'alanube_company_id': '01M1', 'mode': 'hybrid'},
    ));
    await tester.tap(find.text('Cargar certificado'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar certificado digital'), findsOneWidget);
    expect(find.text('Elegir certificado (.p12)'), findsOneWidget);
    // El selector usa el navegador; acá simulamos el archivo elegido.
    Navigator.of(tester.element(find.byType(EcfSigningCertificateDialog))).pop(
      EcfCertificateInput(
        filename: 'anterior.pfx',
        bytes: Uint8List.fromList([1, 2, 3]),
        password: '  clave de prueba  ',
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.certificateSaves.single['filename'], 'anterior.pfx');
    expect(repo.certificateSaves.single['bytes'], [1, 2, 3]);
    expect(repo.certificateSaves.single['password'], '  clave de prueba  ');
    expect(repo.registrations, isEmpty);
    expect(find.text('Certificado guardado.'), findsOneWidget);
  });

  testWidgets('error al guardar certificado se muestra sin romper el alta', (tester) async {
    final repo = await _pump(tester, _json(onboarding: _certifying));
    repo.certificateSaveError = const EcfOnboardingException('El certificado no es válido.');
    await tester.tap(find.text('Cargar certificado'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(EcfSigningCertificateDialog))).pop(
      EcfCertificateInput(
        filename: 'invalido.p12',
        bytes: Uint8List.fromList([0]),
        password: 'prueba',
      ),
    );
    // _run mantiene el indicador activo hasta cerrar el aviso de error.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('El certificado no es válido.'), findsOneWidget);
    expect(repo.certificateSaves, isEmpty);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.text('Cargar certificado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('acceso OFV se consulta al pedirlo y se puede ocultar y copiar sin alterar la clave', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final repo = await _pump(tester, _json(onboarding: _requestedWithOfv));

    expect(find.text('usuario.prueba'), findsOneWidget);
    expect(find.text('Recibida'), findsOneWidget);
    expect(repo.ofvReveals, isEmpty);
    expect(find.text('  Clave de prueba #2026  '), findsNothing);

    await tester.tap(find.text('Ver contraseña'));
    await tester.pumpAndSettle();
    expect(repo.ofvReveals, ['b1']);
    expect(find.text('  Clave de prueba #2026  '), findsOneWidget);

    await tester.tap(find.byTooltip('Ocultar contraseña OFV'));
    await tester.pump();
    expect(find.text('  Clave de prueba #2026  '), findsNothing);
    expect(find.text('••••••••'), findsOneWidget);
    await tester.tap(find.byTooltip('Copiar contraseña OFV'));
    await tester.pump();
    expect(copied, ['  Clave de prueba #2026  ']);
    await tester.tap(find.byTooltip('Mostrar contraseña OFV'));
    await tester.pump();
    expect(find.text('  Clave de prueba #2026  '), findsOneWidget);

    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('  Clave de prueba #2026  '), findsNothing);
    await tester.tap(find.text('Ver contraseña'));
    await tester.pumpAndSettle();
    expect(repo.ofvReveals, ['b1', 'b1']);
  });

  testWidgets('solicitud sin clave OFV muestra que no fue enviada', (tester) async {
    final repo = await _pump(tester, _json(onboarding: {
      ..._certifying,
      'requested_at': '2026-10-27T15:00:00Z',
    }));

    expect(find.text('No enviado'), findsOneWidget);
    expect(find.text('No enviada'), findsOneWidget);
    expect(find.text('Ver contraseña'), findsNothing);
    expect(repo.ofvReveals, isEmpty);
  });

  testWidgets('error al consultar clave OFV permite volver a intentarlo', (tester) async {
    final repo = await _pump(tester, _json(onboarding: _requestedWithOfv));
    repo.ofvError = const EcfOnboardingException('No se pudo leer la contraseña OFV.');

    await tester.tap(find.text('Ver contraseña'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo leer la contraseña OFV.'), findsOneWidget);
    expect(find.text('  Clave de prueba #2026  '), findsNothing);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    repo.ofvError = null;
    await tester.tap(find.text('Ver contraseña'));
    await tester.pumpAndSettle();
    expect(repo.ofvReveals, ['b1', 'b1']);
    expect(find.text('  Clave de prueba #2026  '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refrescar descarta una consulta OFV pendiente', (tester) async {
    final repo = await _pump(tester, _json(onboarding: _requestedWithOfv));
    repo.ofvResponse = Completer<EcfOfvCredentials>();
    await tester.tap(find.text('Ver contraseña'));
    await tester.pump();
    expect(find.text('Consultando contraseña…'), findsOneWidget);
    await tester.tap(find.byTooltip('Refrescar'));
    await tester.pumpAndSettle();
    repo.ofvResponse!.complete(const EcfOfvCredentials(ofvPassword: 'respuesta anterior'));
    await tester.pumpAndSettle();

    expect(find.text('respuesta anterior'), findsNothing);
    expect(find.text('Ver contraseña'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('acceso OFV cabe en pantalla angosta', (tester) async {
    await _pump(tester, _json(onboarding: _requestedWithOfv), width: 480);
    await tester.tap(find.text('Ver contraseña'));
    await tester.pumpAndSettle();

    expect(find.text('  Clave de prueba #2026  '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('simulación: sin set de datos (certificación con proveedor) igual genera', (tester) async {
    final repo = await _pump(tester, _json(onboarding: _certifying));

    expect(find.text('Pruebas de simulación e-CF'), findsOneWidget);
    final generate = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('Generar comprobantes'), matching: find.byType(OutlinedButton)),
    );
    expect(generate.onPressed, isNotNull);

    await tester.tap(find.text('Generar comprobantes'));
    await tester.pumpAndSettle();
    // Sin el set, no se sabe cuántos modelos hay: todo en 1 y editable.
    for (final key in ['31', '32', '32rfce', '33', '34', '41', '43', '44', '45', '46', '47']) {
      final field = tester.widget<TextField>(find.byKey(ValueKey('sim-count-$key')));
      expect(field.controller!.text, '1');
      expect(field.enabled, isTrue);
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Generar'));
    await tester.pumpAndSettle();

    // El modelo lo pone el servidor (el genérico de la DGII): no se pide archivo.
    expect(find.text('Falta el set de datos de la DGII'), findsNothing);
    expect(repo.simulationCounts.single.length, 11);
    expect(find.textContaining('Simulación lista'), findsOneWidget);
  });

  testWidgets('simulación: genera lo que pide el portal (1 de cada uno)', (tester) async {
    final repo = await _pump(tester, {
      ..._json(onboarding: _certifying),
      'test_set': _testSet([
        _case('E310000000001', 'accepted', total: 7080),
        _case('E310000000005', 'accepted', total: 83320),
        _case('E320000000011', 'accepted', via: 'rfce', total: 40120),
        _case('E340000000001', 'accepted', modifies: 'E310000000001'),
      ]),
    });

    await tester.tap(find.text('Generar comprobantes'));
    await tester.pumpAndSettle();
    expect(find.text('Generar la simulación'), findsOneWidget);
    String value(String key) => tester.widget<TextField>(find.byKey(ValueKey('sim-count-$key'))).controller!.text;
    expect(value('31'), '1');
    expect(value('32rfce'), '1');
    expect(value('34'), '1');
    // Sin modelo de ese tipo en el set: 0 y no se puede cambiar.
    expect(value('32'), '0');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('sim-count-47'))).enabled, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Generar'));
    await tester.pumpAndSettle();
    expect(repo.simulationCounts, [
      {'31': 1, '32rfce': 1, '34': 1},
    ]);
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

  // ── Empresa de otra app (Busi Pos Web) ─────────────────────────────────────

  group('empresa de Busi Pos Web', () {
    const owner = EcfOwner.external('x1');
    Map<String, dynamic> external({String? alanubeCompanyId = '01EXT'}) => {
          'id': 'x1',
          'source': 'flutter_shop+',
          'external_id': 'c-1',
          'status': 'in_progress',
          'company_name': 'Maranatha',
          'rnc': '131831151',
          'legal_name': 'MARANATHA SRL',
          'contact_name': 'Ana',
          'contact_phone': '8095550000',
          'ofv_user': 'maranatha.ofv',
          'alanube_company_id': alanubeCompanyId,
          'company_registered': alanubeCompanyId != null,
          'requested_at': '2026-10-30T15:00:00Z',
        };

    testWidgets('mismos pasos de certificación; POS, secuencias y activación quedan en su app', (tester) async {
      await _pump(tester, _json(external: external()), owner: owner);

      expect(find.textContaining('Solicitud desde Busi Pos Web'), findsOneWidget);
      expect(find.textContaining('Usuario OFV: maranatha.ofv'), findsOneWidget);
      expect(find.textContaining('Su app mandó RNC 131831151 · MARANATHA SRL'), findsOneWidget);
      // La empresa que registró su app cuenta como vinculada.
      expect(find.text('01EXT'), findsOneWidget);
      expect(find.text('Registrada por su app (Busi Pos Web)'), findsOneWidget);
      expect(find.text('Postulación en la OFV'), findsOneWidget);
      expect(find.text('Pruebas de simulación e-CF'), findsOneWidget);
      // Nada de lo que vive en la base de su app.
      expect(find.text('Copiar a la POS'), findsNothing);
      expect(find.text('Cargar secuencia'), findsNothing);
      expect(find.text('Verificar'), findsNothing);
      expect(find.textContaining('Las carga el cliente en Busi Pos Web'), findsOneWidget);
      expect(find.text('Encender en su app'), findsOneWidget);
      expect(find.text('Copiar SQL para Busi Pos Web'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('capturar datos arranca con lo que mandó su app', (tester) async {
      await _pump(tester, _json(external: external()), owner: owner);
      await tester.tap(find.text('Capturar datos'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<EcfTaxpayerDialog>(find.byType(EcfTaxpayerDialog));
      expect(dialog.initial.rnc, '131831151');
      expect(dialog.initial.legalName, 'MARANATHA SRL');
    });

    testWidgets('guardar el certificado registra que el cliente lo autorizó', (tester) async {
      final repo = await _pump(tester, _json(external: external(), onboarding: _certifying), owner: owner);
      await tester.tap(find.text('Cargar certificado'));
      await tester.pumpAndSettle();
      expect(find.textContaining('El cliente autorizó a MangoPOS a guardar su certificado'), findsOneWidget);
      Navigator.of(tester.element(find.byType(EcfSigningCertificateDialog))).pop(
        EcfCertificateInput(filename: 'maranatha.p12', bytes: Uint8List.fromList([7]), password: 'prueba'),
      );
      await tester.pumpAndSettle();

      expect(repo.certificateSaves.single['owner'], owner);
      expect(repo.certificateSaves.single['authorized'], isTrue);
    });

    testWidgets('empresa vinculada desde el panel: copia el SQL para enlazarla en su app', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(
        tester,
        _json(external: external(alanubeCompanyId: null), onboarding: {..._certifying, 'alanube_company_id': '01NEW'}),
        owner: owner,
      );

      expect(find.textContaining('Primero enlaza la empresa en su app'), findsOneWidget);
      await tester.tap(find.text('Copiar SQL para Busi Pos Web'));
      await tester.pumpAndSettle();
      expect(copied.single, contains("where company_id = 'c-1'"));
      expect(copied.single, contains("values ('c-1', '01NEW', 'production')"));
    });
  });

  testWidgets('la casilla de autorización bloquea confirmar hasta marcarla', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EcfSigningCertificateDialog(
          title: 'Guardar certificado digital',
          intro: 'Prueba',
          confirmLabel: 'Guardar certificado',
          savedCertificateFilename: 'guardado.p12',
          consentLabel: 'El cliente autorizó',
        ),
      ),
    ));
    FilledButton confirm() => tester.widget<FilledButton>(
          find.ancestor(of: find.text('Guardar certificado'), matching: find.byWidgetPredicate((w) => w is FilledButton)),
        );
    expect(confirm().onPressed, isNull);
    await tester.tap(find.text('El cliente autorizó'));
    await tester.pump();
    expect(confirm().onPressed, isNotNull);
  });

  test('EcfCompany: tomada por otro dueño', () {
    EcfCompany company({String? business, String? external}) => EcfCompany.fromJson({
          'id': '01M1',
          'assigned_to_business_id': business,
          'assigned_to_external_request_id': external,
        });
    expect(company().takenByOtherThan(const EcfOwner.business('b1')), isFalse);
    expect(company(business: 'b1').takenByOtherThan(const EcfOwner.business('b1')), isFalse);
    expect(company(business: 'b1').takenByOtherThan(const EcfOwner.external('b1')), isTrue);
    expect(company(external: 'x1').takenByOtherThan(const EcfOwner.external('x1')), isFalse);
    expect(company(external: 'x1').takenByOtherThan(const EcfOwner.business('b2')), isTrue);
  });
}

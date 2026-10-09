// Alta e-CF en la consola.
//
// Lo que protege: que el paso que marca la sección sea el real — sobre todo
// que un negocio activado antes del panel (Tropella: solo tiene
// business_alanube_settings) no aparezca como "sin empresa" — y que una
// secuencia que la DGII va a rechazar no cuente como lista.

import 'package:flutter_test/flutter_test.dart';
import 'package:mangopos_administrador/domain/models/ecf_onboarding.dart';

Map<String, dynamic> _status({
  Map<String, dynamic>? onboarding,
  Map<String, dynamic>? fiscal,
  List<Map<String, dynamic>> sequences = const [],
  Map<String, dynamic>? settings,
}) =>
    {
      'business': {'id': 'b1', 'business_name': 'Tropella Coffee', 'address': 'Real Food Park'},
      'onboarding': onboarding,
      'fiscal': fiscal,
      'fiscal_sync': onboarding == null ? null : {'rnc_matches': true, 'legal_name_matches': true},
      'sequences': sequences,
      'alanube_settings': settings,
      'company': null,
      'company_error': null,
      'environment': 'production',
    };

const _data = {
  'rnc': '133328828',
  'legal_name': 'TROPELLA COFFEE SRL',
  'fiscal_address': 'GREGORIO LUPERON, No. B 4, GURABO',
};

Map<String, dynamic> _seq(String type, {int end = 1000, int current = 0, String? exp, bool active = true}) => {
      'id': 's-$type',
      'ncf_type': type,
      'range_start': 1,
      'range_end': end,
      'current_number': current,
      'expiration_date': exp,
      'is_active': active,
    };

void main() {
  group('paso actual', () {
    test('negocio nuevo: paso 1', () {
      expect(EcfOnboardingStatus.fromJson(_status()).currentStep, 1);
    });

    test('datos incompletos siguen en paso 1', () {
      final s = EcfOnboardingStatus.fromJson(_status(onboarding: {'rnc': '133328828'}));
      expect(s.currentStep, 1);
    });

    test('datos completos, sin empresa: paso 2', () {
      final s = EcfOnboardingStatus.fromJson(_status(onboarding: _data));
      expect(s.currentStep, 2);
    });

    test('empresa vinculada, sin autorización DGII: paso 3 (certificación)', () {
      final s = EcfOnboardingStatus.fromJson(_status(
        onboarding: {..._data, 'alanube_company_id': '01M11V7B6J4X6FQ5SRAFPVPATV'},
      ));
      expect(s.isCertified, isFalse);
      expect(s.currentStep, 3);
    });

    test('marcado como autorizado, sin secuencias: paso 4', () {
      final s = EcfOnboardingStatus.fromJson(_status(
        onboarding: {
          ..._data,
          'alanube_company_id': '01M1',
          'dgii_authorized_at': '2026-09-17T15:00:00Z',
        },
      ));
      expect(s.isCertified, isTrue);
      expect(s.currentStep, 4);
    });

    test('con secuencia usable cuenta como autorizado: paso 5', () {
      final s = EcfOnboardingStatus.fromJson(_status(
        onboarding: {..._data, 'alanube_company_id': '01M1'},
        sequences: [_seq('E32')],
      ));
      expect(s.isCertified, isTrue);
      expect(s.currentStep, 5);
    });

    test('activado antes del panel (solo settings): toma el ULID de ahí', () {
      final s = EcfOnboardingStatus.fromJson(_status(
        fiscal: {'rnc': '133328828', 'business_legal_name': 'TROPELLA', 'ecf_enabled': false},
        sequences: [_seq('E32')],
        settings: {
          'alanube_company_id': '01M11V7B6J4X6FQ5SRAFPVPATV',
          'environment': 'production',
          'mode': 'hybrid',
        },
      ));
      expect(s.companyId, '01M11V7B6J4X6FQ5SRAFPVPATV');
      expect(s.isProvisioned, isTrue);
      expect(s.currentStep, 5);
    });

    test('activado y con la modalidad encendida: listo', () {
      final s = EcfOnboardingStatus.fromJson(_status(
        onboarding: {..._data, 'alanube_company_id': '01M1'},
        fiscal: {'rnc': '133328828', 'ecf_enabled': true, 'default_ncf_type': 'E32'},
        sequences: [_seq('E32')],
        settings: {'alanube_company_id': '01M1', 'mode': 'hybrid'},
      ));
      expect(s.currentStep, 6);
    });

    test('mode physical no cuenta como activado', () {
      final s = EcfOnboardingStatus.fromJson(_status(
        onboarding: {..._data, 'alanube_company_id': '01M1'},
        fiscal: {'ecf_enabled': true},
        sequences: [_seq('E32')],
        settings: {'alanube_company_id': '01M1', 'mode': 'physical'},
      ));
      expect(s.isProvisioned, isFalse);
      expect(s.currentStep, 5);
    });
  });

  group('secuencias', () {
    test('E31 sin vencimiento no sirve (DGII 145)', () {
      final q = EcfSequence.fromJson(_seq('E31', end: 100));
      expect(q.missingExpiration, isTrue);
      expect(q.isUsable, isFalse);
    });

    test('E32 sin vencimiento sí sirve', () {
      expect(EcfSequence.fromJson(_seq('E32')).isUsable, isTrue);
    });

    test('agotada no sirve', () {
      final q = EcfSequence.fromJson(_seq('E32', end: 100, current: 100));
      expect(q.available, 0);
      expect(q.isUsable, isFalse);
    });

    test('vencida no sirve', () {
      final q = EcfSequence.fromJson(_seq('E31', exp: '2020-01-01'));
      expect(q.isExpired, isTrue);
      expect(q.isUsable, isFalse);
    });

    test('segundo lote: current por debajo del rango cuenta como no usado', () {
      final q = EcfSequence.fromJson({..._seq('E32', end: 200), 'range_start': 101, 'current_number': 0});
      expect(q.available, 100);
    });

    test('solo con E31 inválida no cuenta como lista', () {
      final s = EcfOnboardingStatus.fromJson(_status(
        onboarding: {..._data, 'alanube_company_id': '01M1', 'dgii_authorized_at': '2026-09-17T15:00:00Z'},
        sequences: [_seq('E31', end: 100)],
      ));
      expect(s.currentStep, 4);
    });
  });

  group('empresa y preflight', () {
    test('fecha de Alanube con espacio se parsea', () {
      final c = EcfCompany.fromJson({
        'id': '01M1',
        'certificate': {'name': 'FIRMA', 'end_date': '2027-04-23 21:30:54'},
      });
      expect(c.certificateEndDate, DateTime(2027, 4, 23, 21, 30, 54));
      expect(c.hasCertificate, isTrue);
    });

    test('preflight con rojo no deja activar', () {
      final r = EcfPreflightResult.fromJson({
        'ok': false,
        'wrote': false,
        'checks': [
          {'key': 'rnc', 'level': 'fail', 'message': 'El RNC no coincide'},
          {'key': 'address', 'level': 'warn', 'message': 'Dirección distinta'},
          {'key': 'sequences', 'level': 'ok', 'message': 'OK'},
        ],
      });
      expect(r.hasFailures, isTrue);
      expect(r.warnings, 1);
      expect(r.wrote, isFalse);
    });
  });

  group('certificación', () {
    Map<String, dynamic> testCase(
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

    EcfTestSet testSet(List<Map<String, dynamic>> cases) {
      final s = EcfOnboardingStatus.fromJson({
        ..._status(onboarding: {..._data, 'alanube_company_id': '01M1'}),
        'test_set': {
          'filename': '133051842-08102026121048.xlsx',
          'loaded_at': '2026-10-08T16:10:48Z',
          'session_expires_at': '2026-10-08T17:10:48Z',
          'cases': cases,
        },
      });
      return s.testSet!;
    }

    test('set de pruebas de la DGII: cuenta estados y decide qué se puede hacer', () {
      final t = testSet([
        testCase('E310000000001', 'accepted', total: 1180),
        testCase('E320000000011', 'conditional', via: 'rfce', total: 40120),
        testCase('E320000000005', 'sent', total: 2282785.36),
        testCase('E340000000001', 'pending', modifies: 'E310000000001'),
        testCase('E330000000001', 'error', messages: [
          {'code': '400', 'message': 'Monto invalido'},
        ]),
      ]);
      expect(t.filename, '133051842-08102026121048.xlsx');
      expect(t.sessionExpiresAt, isNotNull);
      expect(t.accepted, 2);
      expect(t.inProcess, 1);
      expect(t.toSend, 2);
      expect(t.summaries, 1);
      expect(t.canSend, isTrue);
      expect(t.canCheck, isTrue);
      expect(t.isComplete, isFalse);
      expect(t.failed.single.messages.single.message, 'Monto invalido');
      expect(t.cases[1].isSummary, isTrue);
      expect(t.cases[1].hasXml, isTrue);
      expect(t.cases[3].hasXml, isFalse);
      expect(t.cases[3].modifies, 'E310000000001');
      expect(t.cases[2].total, 2282785.36);
    });

    test('un rechazo bloquea el envío hasta cargar otro set', () {
      final t = testSet([
        testCase('E310000000001', 'rejected'),
        testCase('E340000000001', 'pending'),
      ]);
      expect(t.rejected.single.statusLabel, 'Rechazado');
      expect(t.canSend, isFalse);
    });

    test('todo aceptado (con o sin observaciones) completa el set', () {
      final t = testSet([
        testCase('E310000000001', 'accepted'),
        testCase('E320000000011', 'conditional', via: 'rfce'),
      ]);
      expect(t.isComplete, isTrue);
      expect(t.canSend, isFalse);
      expect(t.canCheck, isFalse);
    });

    test('aprobaciones comerciales llegan aparte del set de e-CF', () {
      final s = EcfOnboardingStatus.fromJson({
        ..._status(onboarding: {..._data, 'alanube_company_id': '01M1'}),
        'test_set': null,
        'approval_set': {
          'kind': 'acecf',
          'filename': '133051842-09102026121152.xlsx',
          'cases': [testCase('E310000000001', 'accepted', via: 'acecf', total: 7080)],
        },
      });
      expect(s.testSet, isNull);
      final a = s.approvalSet!;
      expect(a.isApprovals, isTrue);
      expect(a.cases.single.isApproval, isTrue);
      expect(a.cases.single.hasXml, isTrue);
      expect(a.isComplete, isTrue);
      expect(a.summaries, 0);
    });

    test('lote de envío: sigue mientras el servidor diga more', () {
      final r = EcfTestSetSendResult.fromJson({
        'sent': 3,
        'more': true,
        'stopped_reason': null,
        'test_set': {'cases': []},
      });
      expect(r.sent, 3);
      expect(r.more, isTrue);
      expect(r.testSet.isEmpty, isTrue);
    });

    test('datos de postulación', () {
      final info = EcfPostulationInfo.fromJson({
        'provider': {
          'software_type': 'EXTERNO',
          'software_name': 'Alanube',
          'software_version': '1',
          'provider_rnc': '132109122',
        },
        'company_urls': {'reception': 'https://r', 'approval': 'https://a', 'authentication': 'https://t'},
      });
      expect(info.providerRnc, '132109122');
      expect(info.authenticationUrl, 'https://t');
    });
  });

  group('solicitudes desde la POS', () {
    test('resumen de solicitud y etiqueta de etapa', () {
      final r = EcfRequestSummary.fromJson({
        'business_id': 'b1',
        'business_name': 'Nuevo Cliente',
        'rnc': '101010101',
        'stage': 'certification',
        'requested_at': '2026-09-17T15:00:00Z',
        'contact_name': 'Ana',
        'contact_phone': '809-555-1234',
        'already_authorized': true,
      });
      expect(r.isActive, isFalse);
      expect(r.stageLabel, 'Certificación DGII');
      expect(r.alreadyAuthorized, isTrue);
    });

    test('borrador trae los datos de la solicitud', () {
      final d = EcfTaxpayerDraft.fromJson({
        'rnc': '101010101',
        'requested_at': '2026-09-17T15:00:00Z',
        'contact_name': 'Ana',
        'contact_phone': '809-555-1234',
        'already_authorized': false,
      });
      expect(d.requestedAt, isNotNull);
      expect(d.contactName, 'Ana');
      expect(d.alreadyAuthorized, isFalse);
    });
  });
}

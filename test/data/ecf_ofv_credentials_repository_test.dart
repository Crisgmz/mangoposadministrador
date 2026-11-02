import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangopos_administrador/data/repositories/ecf_onboarding_repository.dart';
import 'package:mangopos_administrador/domain/models/ecf_onboarding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Functions implements FunctionsClient {
  Object? data;
  FunctionException? error;
  final calls = <Invocation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #invoke) {
      return super.noSuchMethod(invocation);
    }
    calls.add(invocation);
    if (error != null) return Future<FunctionResponse>.error(error!);
    return Future<FunctionResponse>.value(
      FunctionResponse(status: 200, data: data),
    );
  }
}

class _Client implements SupabaseClient {
  _Client(this.functions);

  @override
  final FunctionsClient functions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _b1 = EcfOwner.business('b1');

void main() {
  late _Functions functions;
  late EcfOnboardingRepository repository;

  setUp(() {
    functions = _Functions();
    repository = EcfOnboardingRepository(_Client(functions));
  });

  test(
    'consulta la acción auditada para el negocio y conserva la clave exacta',
    () async {
      functions.data = {
        'ofv_user': 'usuario-prueba',
        'ofv_password': '  Clave de prueba!  ',
      };

      final credentials = await repository.revealOfvPassword(const EcfOwner.business('negocio-prueba'));

      expect(credentials.ofvUser, 'usuario-prueba');
      expect(credentials.ofvPassword, '  Clave de prueba!  ');
      expect(functions.calls, hasLength(1));
      expect(functions.calls.single.positionalArguments, ['ecf-onboarding']);
      expect(functions.calls.single.namedArguments[#body], {
        'action': 'reveal_ofv_password',
        'business_id': 'negocio-prueba',
      });
    },
  );

  test('admite una clave recibida sin usuario', () async {
    functions.data = {'ofv_user': null, 'ofv_password': 'clave-prueba'};

    final credentials = await repository.revealOfvPassword(_b1);

    expect(credentials.ofvUser, isNull);
    expect(credentials.ofvPassword, 'clave-prueba');
  });

  test(
    'registro y firma reutilizan el certificado sin traerlo al panel',
    () async {
      functions.data = {
        'test_set': {'cases': <Map<String, dynamic>>[]},
      };

      await repository.registerCompany(owner: _b1);
      await repository.sendTestSet(owner: _b1, setKind: 'sim');
      await repository.checkTestSet(_b1, setKind: 'sim');

      expect(functions.calls.map((call) => call.namedArguments[#body]), [
        {'action': 'register_company', 'business_id': 'b1'},
        {'action': 'send_test_set', 'business_id': 'b1', 'set_kind': 'sim'},
        {'action': 'check_test_set', 'business_id': 'b1', 'set_kind': 'sim'},
      ]);
    },
  );

  test(
    'carga un certificado conservando los bytes y su contraseña exactos',
    () async {
      functions.data = {'ok': true};

      await repository.saveCertificate(
        owner: _b1,
        certificateFilename: 'negocio.p12',
        certificateBytes: Uint8List.fromList([0x30, 1, 2, 3]),
        certificatePassword: '  Clave de certificado!  ',
      );

      expect(functions.calls.single.namedArguments[#body], {
        'action': 'save_certificate',
        'business_id': 'b1',
        'certificate': {
          'filename': 'negocio.p12',
          'content_base64': 'MAECAw==',
          'password': '  Clave de certificado!  ',
        },
      });
    },
  );

  test(
    'la firma permite elegir otro certificado sin sustituir el guardado',
    () async {
      functions.data = <String, dynamic>{};

      await repository.sendTestSet(
        owner: _b1,
        setKind: 'acecf',
        certificateFilename: 'alternativo.pfx',
        certificateBytes: Uint8List.fromList([0x30, 1]),
        certificatePassword: ' clave-prueba ',
      );

      expect(functions.calls.single.namedArguments[#body], {
        'action': 'send_test_set',
        'business_id': 'b1',
        'set_kind': 'acecf',
        'certificate': {
          'filename': 'alternativo.pfx',
          'content_base64': 'MAE=',
          'password': ' clave-prueba ',
        },
      });
    },
  );

  test(
    'una empresa externa va con external_request_id y la autorización del cliente',
    () async {
      functions.data = {'ok': true};

      await repository.saveCertificate(
        owner: const EcfOwner.external('x1'),
        certificateFilename: 'externa.p12',
        certificateBytes: Uint8List.fromList([0x30]),
        certificatePassword: 'clave',
        clientAuthorizedStorage: true,
      );

      expect(functions.calls.single.namedArguments[#body], {
        'action': 'save_certificate',
        'external_request_id': 'x1',
        'certificate': {
          'filename': 'externa.p12',
          'content_base64': 'MA==',
          'password': 'clave',
        },
        'accept_certificate_storage': true,
      });
    },
  );

  test('una selección incompleta no usa el guardado por accidente', () async {
    await expectLater(
      repository.registerCompany(
        owner: _b1,
        certificateFilename: 'negocio.p12',
      ),
      throwsA(isA<EcfOnboardingException>()),
    );
    await expectLater(
      repository.checkTestSet(_b1, certificatePassword: 'clave-prueba'),
      throwsA(isA<EcfOnboardingException>()),
    );
    expect(functions.calls, isEmpty);
  });

  test('rechaza una respuesta que no contiene una contraseña válida', () async {
    for (final password in [null, '', 123]) {
      functions.data = {'ofv_password': password};
      await expectLater(
        repository.revealOfvPassword(_b1),
        throwsA(isA<EcfOnboardingException>()),
      );
    }
  });

  test(
    'conserva el error del servidor si no se puede auditar la consulta',
    () async {
      functions.error = FunctionException(
        status: 500,
        details: {
          'error': {
            'code': 'audit_failed',
            'message':
                'No se pudo registrar la consulta; la clave no se muestra.',
          },
        },
      );

      await expectLater(
        repository.revealOfvPassword(_b1),
        throwsA(
          isA<EcfOnboardingException>()
              .having((e) => e.code, 'code', 'audit_failed')
              .having((e) => e.message, 'message', contains('no se muestra')),
        ),
      );
    },
  );
}

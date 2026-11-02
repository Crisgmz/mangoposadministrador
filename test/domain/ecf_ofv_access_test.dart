import 'package:flutter_test/flutter_test.dart';
import 'package:mangopos_administrador/domain/models/ecf_onboarding.dart';

void main() {
  test('el estado lee el usuario y sabe que el cliente envió la clave OFV', () {
    final status = EcfOnboardingStatus.fromJson({
      'onboarding': {
        'ofv_user': 'usuario-prueba',
        'ofv_password_updated_at': '2026-10-27T18:00:00Z',
      },
    });

    expect(status.draft?.ofvUser, 'usuario-prueba');
    expect(status.draft?.hasOfvPassword, isTrue);
    expect(status.draft?.ofvPasswordUpdatedAt, DateTime.utc(2026, 10, 27, 18));
  });

  test('una solicitud antigua no anuncia una contraseña que no se envió', () {
    final draft = EcfTaxpayerDraft.fromJson({'rnc': '123456789'});

    expect(draft.ofvUser, isNull);
    expect(draft.ofvPasswordUpdatedAt, isNull);
    expect(draft.hasOfvPassword, isFalse);
  });

  test('editar los datos fiscales no reenvía ni borra credenciales OFV', () {
    final draft = EcfTaxpayerDraft.fromJson({
      'rnc': '123456789',
      'legal_name': 'NEGOCIO DE PRUEBA',
      'ofv_user': 'usuario-prueba',
      'ofv_password_updated_at': '2026-10-27T18:00:00Z',
      'ofv_password': 'clave-prueba',
      'ofv_password_enc': 'v1:cifrado-prueba',
    });

    expect(draft.toJson(), {
      'rnc': '123456789',
      'legal_name': 'NEGOCIO DE PRUEBA',
      'trade_name': null,
      'fiscal_address': null,
      'province': null,
      'municipality': null,
      'email': null,
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mangopos_administrador/domain/models/ecf_onboarding.dart';

void main() {
  test('el estado solo lee los metadatos del certificado recibido', () {
    final status = EcfOnboardingStatus.fromJson({
      'onboarding': {
        'certificate_filename': 'negocio.p12',
        'certificate_updated_at': '2026-10-27T18:00:00Z',
        'certificate_enc': 'v1:secreto-que-no-se-expone',
      },
    });

    expect(status.draft?.hasCertificate, isTrue);
    expect(status.draft?.certificateFilename, 'negocio.p12');
    expect(status.draft?.certificateUpdatedAt, DateTime.utc(2026, 10, 27, 18));
    expect(status.draft!.toJson().keys, isNot(contains('certificate_enc')));
    expect(
      status.draft!.toJson().keys,
      isNot(contains('certificate_filename')),
    );
  });

  test('los negocios anteriores no anuncian un certificado disponible', () {
    for (final row in <Map<String, dynamic>>[
      {},
      {'certificate_filename': 'negocio.p12'},
      {
        'certificate_filename': '',
        'certificate_updated_at': '2026-10-27T18:00:00Z',
      },
    ]) {
      expect(EcfTaxpayerDraft.fromJson(row).hasCertificate, isFalse);
    }
  });
}

// Solicitudes de facturación electrónica que llegan de otras apps.
//
// Lo que protege: que la bandeja distinga lo urgente —una empresa que quedó
// SIN registrar con el proveedor porque su RNC ya existía o su certificado
// falló— de lo que solo espera turno, y que una fila sin nombre de empresa
// igual se pueda leer.

import 'package:flutter_test/flutter_test.dart';
import 'package:mangopos_administrador/domain/models/external_ecf_request.dart';

Map<String, dynamic> _row(Map<String, dynamic> overrides) => {
      'id': 'r1',
      'source': 'flutter_shop+',
      'external_id': 'c-99',
      'status': 'new',
      'company_registered': true,
      ...overrides,
    };

void main() {
  group('bandeja de solicitudes externas', () {
    test('sin registrar con el proveedor es lo que hay que mirar', () {
      final r = ExternalEcfRequest.fromJson(
        _row({'company_registered': false}),
      );

      expect(r.companyRegistered, isFalse);
      expect(r.headline, contains('Sin registrar'));
    });

    test('registrada lo dice sin alarmar', () {
      final r = ExternalEcfRequest.fromJson(_row({}));

      expect(r.headline, 'Registrada con el proveedor');
    });

    test('solo nuevas y en proceso siguen abiertas', () {
      bool open(String status) =>
          ExternalEcfRequest.fromJson(_row({'status': status})).isOpen;

      expect(open('new'), isTrue);
      expect(open('in_progress'), isTrue);
      expect(open('done'), isFalse);
      expect(open('discarded'), isFalse);
    });

    test('el nombre cae en cascada hasta el id', () {
      String name(Map<String, dynamic> o) =>
          ExternalEcfRequest.fromJson(_row(o)).displayName;

      expect(name({'company_name': 'Prueba SRL'}), 'Prueba SRL');
      expect(name({'legal_name': 'PRUEBA SRL'}), 'PRUEBA SRL');
      expect(name({'trade_name': 'Prueba'}), 'Prueba');
      // Sin ningún nombre la fila igual se identifica.
      expect(name({}), 'Empresa c-99');
    });

    test('los campos vacíos llegan como null, no como cadena vacía', () {
      final r = ExternalEcfRequest.fromJson(
        _row({'rnc': '  ', 'contact_name': '', 'requested_at': ''}),
      );

      expect(r.rnc, isNull);
      expect(r.contactName, isNull);
      expect(r.requestedAt, isNull);
    });

    test('lee las fechas y el contacto que manda la otra app', () {
      final r = ExternalEcfRequest.fromJson(
        _row({
          'rnc': '131974602',
          'contact_name': 'Hailerin',
          'contact_phone': '8295059592',
          'already_authorized': true,
          'alanube_company_id': '01J8ABC',
          'requested_at': '2026-09-26T13:00:00Z',
        }),
      );

      expect(r.rnc, '131974602');
      expect(r.contactName, 'Hailerin');
      expect(r.alreadyAuthorized, isTrue);
      expect(r.alanubeCompanyId, '01J8ABC');
      expect(r.requestedAt?.year, 2026);
      expect(r.statusLabel, 'Nueva');
    });
  });
}

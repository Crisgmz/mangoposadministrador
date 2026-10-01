import 'package:flutter_test/flutter_test.dart';
import 'package:mangopos_administrador/domain/models/invoice_payment_result.dart';

void main() {
  test('parsea pagadas, omitidas y cobros corridos', () {
    final r = InvoicePaymentResult.fromJson({
      'dry_run': true,
      'paid': [
        {'invoice_id': 'i1', 'invoice_number': 'MNG-1', 'business_id': 'b1', 'business_name': 'Y', 'total': '4799.00'},
        {'invoice_id': 'i2', 'invoice_number': 'MNG-2', 'business_id': 'b1', 'business_name': 'Y', 'total': 4799},
      ],
      'skipped': [
        {'invoice_id': 'i3', 'invoice_number': 'MNG-3', 'reason': 'paid'},
        {'invoice_id': 'i4', 'reason': 'not_found'},
      ],
      'moved': [
        {'business_id': 'b1', 'business_name': 'Y', 'invoice_number': 'MNG-1',
         'from': '2026-10-01', 'to': '2026-11-01', 'was_past_due': true},
      ],
    });

    expect(r.dryRun, isTrue);
    expect(r.paid, hasLength(2));
    expect(r.totalPaid, 9598);
    expect(r.skipped.map((s) => s.reasonLabel), ['ya estaba pagada', 'ya no existe']);
    expect(r.moved.single.from, DateTime(2026, 10, 1));
    expect(r.moved.single.to, DateTime(2026, 11, 1));
    expect(r.moved.single.wasPastDue, isTrue);
  });

  test('respuesta vacía no rompe', () {
    final r = InvoicePaymentResult.fromJson({'paid': [], 'skipped': [], 'moved': []});
    expect(r.dryRun, isFalse);
    expect(r.totalPaid, 0);
  });
}

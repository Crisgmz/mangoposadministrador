// "Último pago" y "por cobrar" de cada negocio: lo que la matriz de Cobros y
// el detalle muestran de un vistazo.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mangopos_administrador/data/repositories/billing_repository.dart';
import 'package:mangopos_administrador/domain/models/membership_invoice.dart';
import 'package:mangopos_administrador/domain/models/payment_record.dart';

PaymentRecord _payment(String business, String paidAt, int cents,
        {String kind = 'manual', String method = 'transfer', int refunded = 0}) =>
    PaymentRecord.fromJson({
      'kind': kind,
      'id': '$business-$paidAt-$cents',
      'business_id': business,
      'business_name': business,
      'environment': 'production',
      'paid_at': paidAt,
      'amount_cents': cents,
      'method': method,
      'refunded_cents': refunded,
    });

MembershipInvoice _invoice(String id, String business, String status, String periodStart, double total) =>
    MembershipInvoice.fromJson({
      'id': id,
      'invoice_number': 'MNG-$id',
      'business_id': business,
      'business_name': business,
      'plan_type': 'pro',
      'period_start': periodStart,
      'period_end': periodStart,
      'issue_date': periodStart,
      'due_date': periodStart,
      'amount': total,
      'itbis': 0,
      'total': total,
      'status': status,
      'environment': 'production',
    });

void main() {
  test('el último pago junta las facturas pagadas de una vez', () {
    final last = lastPaymentByBusiness([
      // La Cocina Mexicana pagó 3 facturas juntas por transferencia.
      _payment('mex', '2026-11-03T15:00:00Z', 150000),
      _payment('mex', '2026-11-03T15:00:00Z', 150000),
      _payment('mex', '2026-11-03T15:00:00Z', 150000),
      _payment('mex', '2026-09-01T15:00:00Z', 150000),
      // Tarjeta con reembolso parcial: cuenta lo cobrado.
      _payment('maison', '2026-10-16T07:00:00Z', 479999, kind: 'card', method: 'card', refunded: 179999),
    ]);

    expect(last['mex']!.paidAt, DateTime.parse('2026-11-03T15:00:00Z'));
    expect(last['mex']!.invoices, 3);
    expect(last['mex']!.netCents, 450000);
    expect(last['mex']!.methodLabel, 'Transferencia');
    expect(last['maison']!.netCents, 300000);
    expect(last['maison']!.invoices, 1);
    expect(last.containsKey('tropella'), isFalse);
  });

  test('por cobrar: solo pendientes y vencidas, de la más vieja a la más nueva', () async {
    final container = ProviderContainer(overrides: [
      billingOverviewProvider.overrideWith((ref) async => [
            _invoice('3', 'mex', 'pending', '2026-10-05', 1500),
            _invoice('1', 'mex', 'expired', '2026-08-05', 1500),
            _invoice('2', 'mex', 'paid', '2026-09-05', 1500),
            _invoice('4', 'mex', 'void', '2026-07-05', 1500),
            _invoice('5', 'tropella', 'paid', '2026-10-01', 2000),
          ]),
    ]);
    addTearDown(container.dispose);
    await container.read(billingOverviewProvider.future);

    final payable = container.read(payableInvoicesByBusinessProvider).value!;
    expect(payable['mex']!.map((i) => i.id), ['1', '3']);
    expect(payable.containsKey('tropella'), isFalse);
  });
}

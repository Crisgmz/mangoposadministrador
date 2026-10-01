import 'package:flutter_test/flutter_test.dart';
import 'package:mangopos_administrador/domain/models/subscription_charge.dart';

Map<String, dynamic> _charge({
  required int amount,
  int refunded = 0,
  List<String> sales = const [],
}) => {
  'id': 'c1',
  'order_number': 'MP1',
  'attempt_number': 1,
  'amount_cents': amount,
  'status': 'approved',
  'refunded_cents': refunded,
  'pending_refund_cents': 0,
  'refundable_cents': amount - refunded,
  'refunds': [],
  if (sales.isNotEmpty)
    'azul_sales': [
      for (final id in sales)
        {'azul_order_id': id, 'approved_at': '2026-08-16T07:00:10Z'},
    ],
};

void main() {
  test('servidor sin 0048: sin ventas, nunca duplicado', () {
    final c = SubscriptionCharge.fromJson(_charge(amount: 299999));
    expect(c.azulSales, isEmpty);
    expect(c.isDuplicated, isFalse);
    expect(c.duplicateCents, 0);
    expect(c.duplicateOutstandingCents, 0);
  });

  test('una venta: cobro normal', () {
    final c = SubscriptionCharge.fromJson(
      _charge(amount: 299999, sales: ['1']),
    );
    expect(c.isDuplicated, isFalse);
  });

  test('dos ventas: se cobró de más el monto de una', () {
    final c = SubscriptionCharge.fromJson(
      _charge(amount: 299999, sales: ['362377445', '362377446']),
    );
    expect(c.isDuplicated, isTrue);
    expect(c.duplicateCents, 299999);
    expect(c.duplicateOutstandingCents, 299999);
    expect(c.duplicateResolved, isFalse);
    expect(c.azulSales.first.azulOrderId, '362377445');
    expect(c.azulSales.first.approvedAt, DateTime.utc(2026, 8, 16, 7, 0, 10));
  });

  test(
    'un reembolso previo (p. ej. diferencia de precio) no cierra el duplicado',
    () {
      final c = SubscriptionCharge.fromJson(
        _charge(amount: 479999, refunded: 179999, sales: ['a', 'b']),
      );
      expect(c.duplicateResolved, isFalse);
      // Falta 300000 del duplicado y quedan 300000 reembolsables.
      expect(c.duplicateOutstandingCents, 300000);
    },
  );

  test('devuelto lo de más: resuelto y sin saldo pendiente', () {
    final c = SubscriptionCharge.fromJson(
      _charge(amount: 299999, refunded: 299999, sales: ['a', 'b']),
    );
    expect(c.duplicateResolved, isTrue);
    expect(c.duplicateOutstandingCents, 0);
  });

  test('tres ventas: lo pendiente no pasa de lo reembolsable del cobro', () {
    final c = SubscriptionCharge.fromJson(
      _charge(amount: 100000, sales: ['a', 'b', 'c']),
    );
    expect(c.duplicateCents, 200000);
    expect(c.duplicateOutstandingCents, 100000);
  });
}

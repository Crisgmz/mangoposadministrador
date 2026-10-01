import 'package:flutter_test/flutter_test.dart';
import 'package:mangopos_administrador/domain/models/ecf_quota_usage.dart';
import 'package:mangopos_administrador/domain/models/membership_invoice.dart';
import 'package:mangopos_administrador/domain/models/subscription_charge.dart';

void main() {
  test('con cantidad: incluidas, precio, período en curso e historial', () {
    final u = EcfQuotaUsage.fromJson({
      'has_quota': true,
      'included': 5,
      'price_override_cents': 2000,
      'global_price_cents': 1500,
      'unit_price_cents': 2000,
      'counting_since': '2026-09-01T04:00:00Z',
      'next_charge_date': '2026-10-16',
      'current': {
        'has_quota': true,
        'used': 9,
        'extra': 4,
        'overage_cents': 8000,
        'usage_from': '2026-09-16T04:00:00Z',
        'usage_to': '2026-09-18T04:00:00Z',
      },
      'last_30_days': 9,
      'history': [
        {
          'source': 'card',
          'period_start': '2026-09-16',
          'used': 3,
          'extra': 0,
          'overage_cents': 0,
        },
      ],
    });
    expect(u.hasQuota, isTrue);
    expect(u.included, 5);
    expect(u.priceIsCustom, isTrue);
    expect(u.unitPriceCents, 2000);
    expect(u.current.extra, 4);
    expect(u.current.overageCents, 8000);
    expect(u.nextChargeDate, DateTime(2026, 10, 16));
    expect(u.history.single.source, 'card');
  });

  test('sin cantidad: no se cobra aparte', () {
    final u = EcfQuotaUsage.fromJson({
      'has_quota': false,
      'global_price_cents': 1500,
      'unit_price_cents': 1500,
      'current': {'has_quota': false, 'overage_cents': 0},
      'last_30_days': 37,
      'history': [],
    });
    expect(u.hasQuota, isFalse);
    expect(u.included, isNull);
    expect(u.current.used, 0);
    expect(u.last30Days, 37);
  });

  Map<String, dynamic> charge(int amount, int current, int overage) => {
    'id': 'c1',
    'order_number': 'MP1',
    'attempt_number': 1,
    'amount_cents': amount,
    'status': 'approved',
    'current_price_cents': current,
    'refunded_cents': 0,
    'pending_refund_cents': 0,
    'refundable_cents': amount,
    'refunds': [],
    'ecf_overage_cents': overage,
    'ecf_detail': {'extra': overage == 0 ? 0 : overage ~/ 1500},
  };

  test('cobro con extra de e-CF: el extra no se marca como sobreprecio', () {
    final c = SubscriptionCharge.fromJson(charge(305999, 299999, 6000));
    expect(c.ecfExtra, 4);
    expect(c.overPriceCents, isNull);

    // Plan a lista (4,799.99) con precio actual 2,999.99, más el extra:
    // el sobreprecio es solo el del plan.
    final listed = SubscriptionCharge.fromJson(charge(485999, 299999, 6000));
    expect(listed.overPriceCents, 180000);
  });

  test('factura con extra de e-CF', () {
    Map<String, dynamic> invoice(Map<String, dynamic> extra) => {
      'id': 'i1',
      'invoice_number': 'MNG-2026-00001',
      'business_id': 'b1',
      'business_name': 'La Maison Francaise',
      'plan_type': 'pro',
      'period_start': '2026-10-01',
      'period_end': '2026-10-31',
      'issue_date': '2026-10-01T12:00:00Z',
      'due_date': '2026-10-01T12:00:00Z',
      'amount': 3059.99,
      'itbis': 0,
      'total': 3059.99,
      'status': 'pending',
      'environment': 'production',
      ...extra,
    };

    final withExtra = MembershipInvoice.fromJson(
      invoice({
        'ecf_overage_amount': 60,
        'ecf_detail': {'extra': 4, 'unit_price_cents': 1500},
      }),
    );
    expect(withExtra.ecfOverageAmount, 60);
    expect(withExtra.ecfExtra, 4);
    expect(withExtra.ecfUnitPriceCents, 1500);

    final before0051 = MembershipInvoice.fromJson(invoice({}));
    expect(before0051.ecfOverageAmount, 0);
    expect(before0051.ecfExtra, isNull);
  });
}

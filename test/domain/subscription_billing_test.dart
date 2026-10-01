// Precio especial en el modelo de suscripción de la consola.
//
// Lo que protege: que la tarjeta muestre el monto que REALMENTE se va a cobrar
// — con precio especial, sin él, con uno cargado que ya no aplica — y que una
// respuesta vieja del backend (antes de 0043) no rompa ni invente descuentos.

import 'package:flutter_test/flutter_test.dart';
import 'package:mangopos_administrador/domain/models/subscription_billing.dart';

Map<String, dynamic> _base() => {
  'membership_id': 'm1',
  'business_id': 'b1',
  'billing_status': 'active',
  'current_attempt_number': 0,
  'plan_code': 'pro',
  'plan_name': 'Pro',
  'price_cents_monthly': 479900,
  'currency_code': 'DOP',
};

void main() {
  group('precio especial', () {
    test('respuesta previa a 0043: sin descuento y el cobro es la lista', () {
      final b = SubscriptionBilling.fromJson(_base());

      expect(b.hasPriceOverride, isFalse);
      expect(b.priceOverrideStale, isFalse);
      expect(b.effectivePriceCents, isNull);
      expect(b.chargePriceCents, 479900);
    });

    test('vigente: se cobra el precio especial', () {
      final b = SubscriptionBilling.fromJson({
        ..._base(),
        'price_override_cents': 300000,
        'price_override_plan_code': 'pro',
        'price_override_applies': true,
        'effective_price_cents': 300000,
        'price_override_reason': 'cliente fundador',
        'price_override_ends_on': '2026-12-31',
      });

      expect(b.hasPriceOverride, isTrue);
      expect(b.priceOverrideApplies, isTrue);
      expect(b.priceOverrideStale, isFalse);
      expect(b.chargePriceCents, 300000);
      expect(b.priceOverrideReason, 'cliente fundador');
      expect(b.priceOverrideEndsOn, DateTime(2026, 12, 31));
    });

    test('cargado pero sin aplicar (cambió de plan): se marca y cobra lista', () {
      final b = SubscriptionBilling.fromJson({
        ..._base(),
        'plan_code': 'basic',
        'price_cents_monthly': 150000,
        'price_override_cents': 300000,
        'price_override_plan_code': 'pro',
        'price_override_applies': false,
        'effective_price_cents': 150000,
      });

      expect(b.priceOverrideStale, isTrue);
      // Lo decide el servidor: nunca los 3,000 acordados para Pro.
      expect(b.chargePriceCents, 150000);
    });
  });
}

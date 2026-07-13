import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../domain/models/subscription_billing.dart';

/// Suscripción / cobro automático (Azul) por negocio. Todo vía RPCs
/// `security definer` gateadas por `is_platform_operator()` (migración 0039).
class SubscriptionBillingRepository {
  SubscriptionBillingRepository(this._client);

  final SupabaseClient _client;

  /// Estado de facturación de la membresía ancla. `null` si el negocio aún
  /// no tiene membresía marcada como ancla de facturación.
  Future<SubscriptionBilling?> get(String businessId) async {
    final raw = await _client.rpc(
      'admin_get_business_billing',
      params: {'p_business_id': businessId},
    );
    if (raw == null) return null;
    return SubscriptionBilling.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Actualiza estado/fechas de la suscripción. Solo se envían los campos
  /// no nulos; el resto conserva su valor. `reason` es obligatoria (audit).
  ///
  /// - Quitar trial + activar producción: `billingStatus: 'active'`,
  ///   `clearTrial: true`, `nextBillingDate` + período.
  /// - Solo mover fechas: pasar únicamente las fechas.
  Future<SubscriptionBilling?> update({
    required String businessId,
    required String reason,
    String? billingStatus,
    DateTime? trialEndsAt,
    bool clearTrial = false,
    DateTime? nextBillingDate,
    DateTime? currentPeriodStart,
    DateTime? currentPeriodEnd,
    bool resetAttempts = false,
  }) async {
    final raw = await _client.rpc(
      'admin_update_subscription_billing',
      params: {
        'p_business_id': businessId,
        'p_reason': reason,
        'p_billing_status': billingStatus,
        'p_trial_ends_at': trialEndsAt?.toUtc().toIso8601String(),
        'p_clear_trial': clearTrial,
        'p_next_billing_date': _dateOnly(nextBillingDate),
        'p_current_period_start': _dateOnly(currentPeriodStart),
        'p_current_period_end': _dateOnly(currentPeriodEnd),
        'p_reset_attempts': resetAttempts,
      },
    );
    if (raw == null) return null;
    return SubscriptionBilling.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Las columnas de fechas de cobro son `date` (sin hora ni zona).
  static String? _dateOnly(DateTime? d) {
    if (d == null) return null;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}

final subscriptionBillingRepositoryProvider =
    Provider<SubscriptionBillingRepository>((ref) {
  return SubscriptionBillingRepository(ref.watch(supabaseProvider));
});

/// Estado de suscripción por negocio (family por businessId).
final subscriptionBillingProvider =
    FutureProvider.family<SubscriptionBilling?, String>((ref, businessId) {
  return ref.watch(subscriptionBillingRepositoryProvider).get(businessId);
});

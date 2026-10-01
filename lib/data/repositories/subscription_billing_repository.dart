import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../domain/models/subscription_billing.dart';
import '../../domain/models/subscription_charge.dart';

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

  /// Fija un precio mensual especial para el plan ACTUAL del negocio
  /// (migración 0043). Tiene que ser menor al de lista; el servidor lo valida.
  /// [endsOn] es el último día en que aplica (`null` = sin vencimiento).
  Future<SubscriptionBilling?> setPriceOverride({
    required String businessId,
    required double priceMonthly,
    required String reason,
    DateTime? endsOn,
  }) async {
    final raw = await _client.rpc(
      'admin_set_price_override',
      params: {
        'p_business_id': businessId,
        'p_price_monthly': priceMonthly,
        'p_reason': reason,
        'p_ends_on': _dateOnly(endsOn),
      },
    );
    if (raw == null) return null;
    return SubscriptionBilling.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Quita el precio especial: el próximo cobro vuelve al precio de lista.
  Future<SubscriptionBilling?> clearPriceOverride({
    required String businessId,
    required String reason,
  }) async {
    final raw = await _client.rpc(
      'admin_clear_price_override',
      params: {'p_business_id': businessId, 'p_reason': reason},
    );
    if (raw == null) return null;
    return SubscriptionBilling.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Cobros con tarjeta del negocio con sus reembolsos (migración 0046).
  Future<List<SubscriptionCharge>> listCharges(
    String businessId, {
    int limit = 24,
  }) async {
    final raw = await _client.rpc(
      'admin_list_business_charges',
      params: {'p_business_id': businessId, 'p_limit': limit},
    );
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((r) => SubscriptionCharge.fromJson(Map<String, dynamic>.from(r)))
        .toList(growable: false);
  }

  /// Devuelve [amountCents] de un cobro a la tarjeta, vía la Edge Function
  /// `admin-azul-refund` de este repo (valida operador y saldo, habla con Azul).
  ///
  /// No lanza si Azul rechaza o no confirma: eso viene en el resultado. Lanza
  /// [SubscriptionRefundException] si el servidor rechazó el pedido (monto
  /// mayor al disponible, cobro no reembolsable, sin permiso…).
  Future<RefundActionResult> refundCharge({
    required String chargeId,
    required int amountCents,
    required String reason,
  }) {
    return _invokeRefund({
      'action': 'refund',
      'charge_id': chargeId,
      'amount_cents': amountCents,
      'reason': reason,
    });
  }

  /// Resuelve un reembolso `pending` preguntándole a Azul (VerifyPayment).
  Future<RefundActionResult> verifyRefund(String refundId) {
    return _invokeRefund({'action': 'verify', 'refund_id': refundId});
  }

  Future<RefundActionResult> _invokeRefund(Map<String, dynamic> body) async {
    final dynamic data;
    try {
      final res =
          await _client.functions.invoke('admin-azul-refund', body: body);
      data = res.data;
    } on FunctionException catch (e) {
      throw SubscriptionRefundException(_functionErrorMessage(e));
    }
    if (data is! Map) {
      throw const SubscriptionRefundException(
        'Respuesta inesperada del servidor.',
      );
    }
    final refund = data['refund'];
    return RefundActionResult(
      approved: data['ok'] == true,
      message: data['message']?.toString() ?? '',
      status: refund is Map ? refund['status']?.toString() : null,
    );
  }

  static String _functionErrorMessage(FunctionException e) {
    final details = e.details;
    if (details is Map) {
      final err = details['error'];
      if (err is Map && err['message'] != null) {
        return err['message'].toString();
      }
    }
    // El edge runtime responde 500 "worker boot error" cuando la carpeta de la
    // función no existe en el volumen: no está desplegada.
    final raw = details?.toString() ?? '';
    if (e.status == 404 || raw.contains('InvalidWorkerCreation')) {
      return 'La función admin-azul-refund no está desplegada en el servidor.';
    }
    return 'No se pudo completar el reembolso (HTTP ${e.status}).';
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

/// Error de un pedido de reembolso con mensaje apto para mostrar.
class SubscriptionRefundException implements Exception {
  const SubscriptionRefundException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Cobros con tarjeta + reembolsos por negocio (family por businessId).
final subscriptionChargesProvider =
    FutureProvider.family<List<SubscriptionCharge>, String>((ref, businessId) {
  return ref.watch(subscriptionBillingRepositoryProvider).listCharges(businessId);
});

/// Estado de suscripción por negocio (family por businessId).
final subscriptionBillingProvider =
    FutureProvider.family<SubscriptionBilling?, String>((ref, businessId) {
  return ref.watch(subscriptionBillingRepositoryProvider).get(businessId);
});

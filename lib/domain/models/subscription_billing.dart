/// Estado de suscripción/cobro automático (Azul) de un negocio, tal como lo
/// devuelve la RPC `admin_get_business_billing`: membresía ancla + plan +
/// tarjeta default + último cobro.
class SubscriptionBilling {
  const SubscriptionBilling({
    required this.membershipId,
    required this.businessId,
    required this.billingStatus,
    required this.currentAttemptNumber,
    this.planCode,
    this.planName,
    this.priceCentsMonthly,
    this.currencyCode,
    this.trialEndsAt,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.nextBillingDate,
    this.consentGrantedAt,
    this.suspendedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.card,
    this.lastCharge,
  });

  final String membershipId;
  final String businessId;

  /// `trial | active | past_due | suspended | cancelled` (check en BD).
  final String billingStatus;
  final int currentAttemptNumber;
  final String? planCode;
  final String? planName;
  final int? priceCentsMonthly;
  final String? currencyCode;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? nextBillingDate;
  final DateTime? consentGrantedAt;
  final DateTime? suspendedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final BillingCard? card;
  final BillingLastCharge? lastCharge;

  bool get isTrial => billingStatus == 'trial';
  bool get hasVerifiedCard => card?.status == 'verified';

  /// Elegibilidad para el cron de cobro automático (`azul_charge_due`):
  /// estado active/past_due + plan asignado + tarjeta verificada + <3 intentos.
  bool get autoChargeReady =>
      (billingStatus == 'active' || billingStatus == 'past_due') &&
      planCode != null &&
      hasVerifiedCard &&
      currentAttemptNumber < 3;

  /// Razones (en español, para UI) por las que el cobro automático NO correrá.
  List<String> get autoChargeBlockers {
    final reasons = <String>[];
    if (billingStatus == 'trial') {
      reasons.add('Está en trial: el cron solo cobra estados Activa/Atrasada');
    } else if (billingStatus == 'suspended') {
      reasons.add('Suscripción suspendida');
    } else if (billingStatus == 'cancelled') {
      reasons.add('Suscripción cancelada');
    }
    if (planCode == null) reasons.add('Sin plan asignado (plan_id vacío)');
    if (card == null) {
      reasons.add('Sin tarjeta registrada');
    } else if (!hasVerifiedCard) {
      reasons.add('Tarjeta sin verificar (${card!.status})');
    }
    if (currentAttemptNumber >= 3) {
      reasons.add('Agotó los 3 intentos de cobro');
    }
    if (nextBillingDate == null) reasons.add('Sin fecha de próximo cobro');
    return reasons;
  }

  factory SubscriptionBilling.fromJson(Map<String, dynamic> json) {
    return SubscriptionBilling(
      membershipId: json['membership_id'] as String,
      businessId: json['business_id'] as String,
      billingStatus: (json['billing_status'] as String?) ?? 'trial',
      currentAttemptNumber: _toInt(json['current_attempt_number']),
      planCode: json['plan_code'] as String?,
      planName: json['plan_name'] as String?,
      priceCentsMonthly: json['price_cents_monthly'] == null
          ? null
          : _toInt(json['price_cents_monthly']),
      currencyCode: json['currency_code'] as String?,
      trialEndsAt: _parseDate(json['trial_ends_at']),
      currentPeriodStart: _parseDate(json['current_period_start']),
      currentPeriodEnd: _parseDate(json['current_period_end']),
      nextBillingDate: _parseDate(json['next_billing_date']),
      consentGrantedAt: _parseDate(json['consent_granted_at']),
      suspendedAt: _parseDate(json['suspended_at']),
      cancelledAt: _parseDate(json['cancelled_at']),
      cancellationReason: json['cancellation_reason'] as String?,
      card: json['card'] == null
          ? null
          : BillingCard.fromJson(
              Map<String, dynamic>.from(json['card'] as Map)),
      lastCharge: json['last_charge'] == null
          ? null
          : BillingLastCharge.fromJson(
              Map<String, dynamic>.from(json['last_charge'] as Map)),
    );
  }
}

/// Tarjeta default tokenizada (Azul DataVault) — solo datos enmascarados.
class BillingCard {
  const BillingCard({
    required this.status,
    this.brand,
    this.masked,
    this.expiration,
  });

  /// `pending_verification | verified | failed_verification | expired | revoked`.
  final String status;
  final String? brand;
  final String? masked;

  /// Formato AAAAMM (ej. `202812`).
  final String? expiration;

  factory BillingCard.fromJson(Map<String, dynamic> json) {
    return BillingCard(
      status: (json['status'] as String?) ?? 'pending_verification',
      brand: json['brand'] as String?,
      masked: json['masked'] as String?,
      expiration: json['expiration'] as String?,
    );
  }
}

/// Último cobro registrado en `azul_charges` para la membresía ancla.
class BillingLastCharge {
  const BillingLastCharge({
    required this.status,
    this.amountCents,
    this.attemptedAt,
    this.responseMessage,
  });

  /// `pending | approved | declined | error | voided`.
  final String status;
  final int? amountCents;
  final DateTime? attemptedAt;
  final String? responseMessage;

  factory BillingLastCharge.fromJson(Map<String, dynamic> json) {
    return BillingLastCharge(
      status: (json['status'] as String?) ?? 'pending',
      amountCents:
          json['amount_cents'] == null ? null : _toInt(json['amount_cents']),
      attemptedAt: _parseDate(json['attempted_at']),
      responseMessage: json['response_message'] as String?,
    );
  }
}

int _toInt(dynamic raw) {
  if (raw == null) return 0;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString()) ?? 0;
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

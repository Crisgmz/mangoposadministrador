/// Estado de acceso al POS de un negocio — bloqueo por falta de pago.
///
/// Espejo del jsonb de `admin_get_business_access` (migración 0040), que a su
/// vez delega en `fn_business_access_state` del repo mangospos. El motor de
/// estado vive en la BD: acá no se recalcula nada, solo se presenta.
class BusinessAccess {
  const BusinessAccess({
    required this.businessId,
    required this.state,
    required this.reason,
    required this.enforced,
    required this.enforcement,
    required this.lockMode,
    required this.graceDays,
    required this.offlineMaxDays,
    this.lockedAt,
    this.graceEndsAt,
    this.scheduledLockAt,
    this.overrideUntil,
    this.customerMessage,
    this.lockReason,
    this.contactName,
    this.contactPhone,
    this.businessStatus,
    this.billingStatus,
    this.planName,
    this.amountCents,
    this.currencyCode,
    this.nextBillingDate,
    this.attemptNumber = 0,
  });

  final String businessId;

  /// `ok | warning | grace | locked`.
  final String state;

  /// `none | manual_lock | account_inactive | subscription_suspended |
  /// subscription_cancelled | scheduled_cutoff | payment_overdue |
  /// trial_expired | extension_granted`.
  final String reason;

  /// Si es false, el POS NO aplica el bloqueo aunque `state` sea 'locked'.
  final bool enforced;

  /// `inherit | on | off` — enforcement de este negocio.
  final String enforcement;

  /// `auto | forced_locked | forced_open`.
  final String lockMode;

  final int graceDays;
  final int offlineMaxDays;

  final DateTime? lockedAt;
  final DateTime? graceEndsAt;
  final DateTime? scheduledLockAt;
  final DateTime? overrideUntil;
  final String? customerMessage;
  final String? lockReason;
  final String? contactName;
  final String? contactPhone;
  final String? businessStatus;
  final String? billingStatus;
  final String? planName;
  final int? amountCents;
  final String? currencyCode;
  final DateTime? nextBillingDate;
  final int attemptNumber;

  bool get isLocked => state == 'locked';
  bool get isGrace => state == 'grace';
  bool get isWarning => state == 'warning';
  bool get isOk => state == 'ok';

  bool get isManuallyLocked => lockMode == 'forced_locked';
  bool get hasExtension =>
      lockMode == 'forced_open' &&
      (overrideUntil == null || overrideUntil!.isAfter(DateTime.now()));
  bool get hasSchedule =>
      scheduledLockAt != null && scheduledLockAt!.isAfter(DateTime.now());

  /// Etiqueta del estado para la UI.
  String get stateLabel {
    switch (state) {
      case 'locked':
        return 'Bloqueado';
      case 'grace':
        return 'En gracia';
      case 'warning':
        return 'Con aviso';
      default:
        return 'Activo';
    }
  }

  /// Explicación operativa (para el operador, no para el cliente).
  String get reasonLabel {
    switch (reason) {
      case 'manual_lock':
        return 'Bloqueo manual del operador';
      case 'account_inactive':
        return 'Cuenta desactivada (businesses.status = inactive)';
      case 'subscription_suspended':
        return 'Suscripción suspendida por cobros fallidos';
      case 'subscription_cancelled':
        return 'Suscripción cancelada';
      case 'scheduled_cutoff':
        return 'Corte programado';
      case 'payment_overdue':
        return 'Pago vencido';
      case 'trial_expired':
        return 'Período de prueba vencido';
      case 'extension_granted':
        return 'Prórroga vigente';
      default:
        return 'Sin novedad';
    }
  }

  /// Por qué el bloqueo no se está aplicando, si aplica. Null si sí se aplica
  /// o si no hay nada que aplicar.
  String? get notEnforcedNote {
    if (enforced || state == 'ok') return null;
    if (enforcement == 'off') {
      return 'Este negocio tiene el bloqueo desactivado explícitamente.';
    }
    return 'El bloqueo global está apagado, así que el POS no lo aplica.';
  }

  factory BusinessAccess.fromJson(Map<String, dynamic> json) {
    return BusinessAccess(
      businessId: json['business_id'] as String,
      state: (json['state'] as String?) ?? 'ok',
      reason: (json['reason'] as String?) ?? 'none',
      enforced: (json['enforced'] as bool?) ?? false,
      enforcement: (json['enforcement'] as String?) ?? 'inherit',
      lockMode: (json['lock_mode'] as String?) ?? 'auto',
      graceDays: (json['grace_days'] as num?)?.toInt() ?? 5,
      offlineMaxDays: (json['offline_max_days'] as num?)?.toInt() ?? 7,
      lockedAt: _ts(json['locked_at']),
      graceEndsAt: _ts(json['grace_ends_at']),
      scheduledLockAt: _ts(json['scheduled_lock_at']),
      overrideUntil: _ts(json['override_until']),
      customerMessage: json['customer_message'] as String?,
      lockReason: json['lock_reason'] as String?,
      contactName: json['contact_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
      businessStatus: json['business_status'] as String?,
      billingStatus: json['billing_status'] as String?,
      planName: json['plan_name'] as String?,
      amountCents: (json['amount_cents'] as num?)?.toInt(),
      currencyCode: json['currency_code'] as String?,
      nextBillingDate: _ts(json['next_billing_date']),
      attemptNumber: (json['attempt_number'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? _ts(Object? v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }
}

/// Política global del bloqueo (`platform_access_policy`, fila única).
class AccessPolicy {
  const AccessPolicy({
    required this.enforcementEnabled,
    required this.defaultGraceDays,
    required this.lockOnPastDue,
    required this.lockOnTrialExpired,
    required this.offlineMaxDays,
    this.defaultCustomerMessage,
    this.contactName,
    this.contactPhone,
    this.contactEmail,
    this.updatedAt,
  });

  /// Kill switch maestro. En false ningún POS bloquea.
  final bool enforcementEnabled;
  final int defaultGraceDays;
  final bool lockOnPastDue;
  final bool lockOnTrialExpired;
  final int offlineMaxDays;
  final String? defaultCustomerMessage;
  final String? contactName;
  final String? contactPhone;
  final String? contactEmail;
  final DateTime? updatedAt;

  factory AccessPolicy.fromJson(Map<String, dynamic> json) {
    return AccessPolicy(
      enforcementEnabled: (json['enforcement_enabled'] as bool?) ?? false,
      defaultGraceDays: (json['default_grace_days'] as num?)?.toInt() ?? 5,
      lockOnPastDue: (json['lock_on_past_due'] as bool?) ?? true,
      lockOnTrialExpired: (json['lock_on_trial_expired'] as bool?) ?? false,
      offlineMaxDays: (json['offline_max_days'] as num?)?.toInt() ?? 7,
      defaultCustomerMessage: json['default_customer_message'] as String?,
      contactName: json['contact_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
      contactEmail: json['contact_email'] as String?,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'].toString())?.toLocal(),
    );
  }
}

/// Fila de la cartera de cobranza (`admin_list_locked_businesses`): negocios
/// bloqueados, en gracia o con aviso.
class AffectedBusiness {
  const AffectedBusiness({
    required this.businessId,
    required this.businessName,
    required this.state,
    required this.reason,
    required this.enforced,
    this.lockedAt,
    this.graceEndsAt,
    this.billingStatus,
  });

  final String businessId;
  final String businessName;
  final String state;
  final String reason;
  final bool enforced;
  final DateTime? lockedAt;
  final DateTime? graceEndsAt;
  final String? billingStatus;

  bool get isLocked => state == 'locked';

  factory AffectedBusiness.fromJson(Map<String, dynamic> json) {
    return AffectedBusiness(
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? 'Sin nombre',
      state: (json['state'] as String?) ?? 'ok',
      reason: (json['reason'] as String?) ?? 'none',
      enforced: (json['enforced'] as bool?) ?? false,
      lockedAt: BusinessAccess._ts(json['locked_at']),
      graceEndsAt: BusinessAccess._ts(json['grace_ends_at']),
      billingStatus: json['billing_status'] as String?,
    );
  }
}

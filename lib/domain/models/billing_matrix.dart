import '_json_helpers.dart';
import 'business_environment.dart';
import 'subscription_billing.dart';

/// Estado de la factura de un mes dentro de la matriz. `none` es el caso en
/// que ese negocio simplemente no tiene factura generada para el período.
enum MonthCellStatus { none, pending, paid, expired, voided }

extension MonthCellStatusX on MonthCellStatus {
  static MonthCellStatus fromText(String? raw) {
    switch (raw) {
      case 'paid':
        return MonthCellStatus.paid;
      case 'pending':
        return MonthCellStatus.pending;
      case 'expired':
        return MonthCellStatus.expired;
      case 'void':
        return MonthCellStatus.voided;
      default:
        return MonthCellStatus.none;
    }
  }

  String get label {
    switch (this) {
      case MonthCellStatus.none:
        return 'Sin factura';
      case MonthCellStatus.pending:
        return 'Pendiente';
      case MonthCellStatus.paid:
        return 'Pagada';
      case MonthCellStatus.expired:
        return 'Vencida';
      case MonthCellStatus.voided:
        return 'Anulada';
    }
  }
}

/// Una celda de la matriz: el período y la factura que le corresponde.
class BillingMonthCell {
  const BillingMonthCell({
    required this.periodStart,
    required this.status,
    this.invoiceId,
    this.invoiceNumber,
    this.total,
    this.dueDate,
    this.paidAt,
    this.paymentMethod,
  });

  final DateTime periodStart;
  final MonthCellStatus status;
  final String? invoiceId;
  final String? invoiceNumber;
  final double? total;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final String? paymentMethod;

  bool get hasInvoice => status != MonthCellStatus.none;

  factory BillingMonthCell.fromJson(Map<String, dynamic> json) {
    return BillingMonthCell(
      periodStart: parseDate(json['period_start']) ?? DateTime.now(),
      status: MonthCellStatusX.fromText(json['status'] as String?),
      invoiceId: json['invoice_id'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      total: json['total'] == null ? null : parseDouble(json['total']),
      dueDate: parseDate(json['due_date']),
      paidAt: parseDate(json['paid_at']),
      paymentMethod: json['payment_method'] as String?,
    );
  }
}

/// Una fila de la matriz de facturación: el negocio, su suscripción ancla,
/// la tarjeta default y el historial mes a mes. Lo devuelve la RPC
/// `admin_billing_matrix` (migración 0042).
class BillingMatrixRow {
  const BillingMatrixRow({
    required this.businessId,
    required this.businessName,
    required this.domain,
    required this.environment,
    required this.businessStatus,
    required this.months,
    required this.cardsCount,
    required this.currentAttemptNumber,
    required this.isBillingAnchor,
    this.membershipId,
    this.billingStatus,
    this.planType,
    this.planCode,
    this.planName,
    this.monthlyFee,
    this.listMonthlyFee,
    this.hasPriceOverride = false,
    this.trialEndsAt,
    this.nextBillingDate,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.consentGrantedAt,
    this.card,
    this.lastCharge,
  });

  final String businessId;
  final String businessName;
  final String domain;
  final BusinessEnvironment environment;

  /// `active | inactive` de `businesses.status`.
  final String businessStatus;

  final String? membershipId;
  final bool isBillingAnchor;

  /// `trial | active | past_due | suspended | cancelled`; `null` si el negocio
  /// no tiene ninguna membresía.
  final String? billingStatus;
  final String? planType;
  final String? planCode;
  final String? planName;

  /// Tarifa mensual que se le cobra en RD$: precio especial si tiene uno
  /// vigente (migración 0043), si no catálogo de planes o tabla legacy.
  final double? monthlyFee;

  /// Precio de lista del plan, para comparar con [monthlyFee].
  final double? listMonthlyFee;

  /// Si [monthlyFee] es un precio especial acordado con el cliente.
  final bool hasPriceOverride;

  final DateTime? trialEndsAt;
  final DateTime? nextBillingDate;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? consentGrantedAt;
  final int currentAttemptNumber;

  /// Tarjeta marcada como default en `azul_payment_methods`.
  final BillingCard? card;
  final int cardsCount;
  final BillingLastCharge? lastCharge;

  /// Una celda por mes de la ventana, en orden cronológico.
  final List<BillingMonthCell> months;

  bool get hasCard => card != null;
  bool get cardVerified => card?.status == 'verified';
  bool get isActiveBusiness => businessStatus == 'active';

  /// Días hasta el próximo cobro. Negativo si la fecha ya pasó.
  int? get daysToNextCharge {
    final d = nextBillingDate;
    if (d == null) return null;
    final today = DateTime.now();
    final a = DateTime(d.year, d.month, d.day);
    final b = DateTime(today.year, today.month, today.day);
    return a.difference(b).inDays;
  }

  /// Misma regla que el cron `azul_charge_due`: estado cobrable, plan
  /// asignado, tarjeta verificada y menos de 3 intentos.
  bool get autoChargeReady =>
      (billingStatus == 'active' || billingStatus == 'past_due') &&
      planCode != null &&
      cardVerified &&
      currentAttemptNumber < 3 &&
      nextBillingDate != null;

  /// Razones por las que el cobro automático no correrá, para el tooltip.
  List<String> get autoChargeBlockers {
    final reasons = <String>[];
    switch (billingStatus) {
      case null:
        reasons.add('El negocio no tiene membresía');
      case 'trial':
        reasons.add('En trial: el cron solo cobra Activa/Atrasada');
      case 'suspended':
        reasons.add('Suscripción suspendida');
      case 'cancelled':
        reasons.add('Suscripción cancelada');
    }
    if (planCode == null) reasons.add('Sin plan del catálogo asignado');
    if (card == null) {
      reasons.add('Sin tarjeta registrada');
    } else if (!cardVerified) {
      reasons.add('Tarjeta sin verificar (${card!.status})');
    }
    if (currentAttemptNumber >= 3) reasons.add('Agotó los 3 intentos');
    if (nextBillingDate == null) reasons.add('Sin fecha de próximo cobro');
    return reasons;
  }

  /// Cuántos meses de la ventana quedaron sin cobrar (pendiente o vencida).
  int get unpaidMonths => months
      .where((m) =>
          m.status == MonthCellStatus.pending ||
          m.status == MonthCellStatus.expired)
      .length;

  /// Total facturado y cobrado dentro de la ventana.
  double get paidInWindow => months
      .where((m) => m.status == MonthCellStatus.paid)
      .fold<double>(0, (sum, m) => sum + (m.total ?? 0));

  double get unpaidInWindow => months
      .where((m) =>
          m.status == MonthCellStatus.pending ||
          m.status == MonthCellStatus.expired)
      .fold<double>(0, (sum, m) => sum + (m.total ?? 0));

  factory BillingMatrixRow.fromJson(Map<String, dynamic> json) {
    final rawMonths = (json['months'] as List<dynamic>?) ?? const [];
    return BillingMatrixRow(
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      domain: (json['domain'] as String?) ?? '',
      environment: BusinessEnvironmentX.fromText(json['environment'] as String?),
      businessStatus: (json['business_status'] as String?) ?? 'active',
      membershipId: json['membership_id'] as String?,
      isBillingAnchor: json['is_billing_anchor'] == true,
      billingStatus: json['billing_status'] as String?,
      planType: json['plan_type'] as String?,
      planCode: json['plan_code'] as String?,
      planName: json['plan_name'] as String?,
      monthlyFee:
          json['monthly_fee'] == null ? null : parseDouble(json['monthly_fee']),
      listMonthlyFee: json['list_monthly_fee'] == null
          ? null
          : parseDouble(json['list_monthly_fee']),
      hasPriceOverride: json['has_price_override'] == true,
      trialEndsAt: parseDate(json['trial_ends_at']),
      nextBillingDate: parseDate(json['next_billing_date']),
      currentPeriodStart: parseDate(json['current_period_start']),
      currentPeriodEnd: parseDate(json['current_period_end']),
      consentGrantedAt: parseDate(json['consent_granted_at']),
      currentAttemptNumber: parseInt(json['current_attempt_number']),
      cardsCount: parseInt(json['cards_count']),
      card: json['card'] == null
          ? null
          : BillingCard.fromJson(Map<String, dynamic>.from(json['card'] as Map)),
      lastCharge: json['last_charge'] == null
          ? null
          : BillingLastCharge.fromJson(
              Map<String, dynamic>.from(json['last_charge'] as Map)),
      months: rawMonths
          .map((m) => BillingMonthCell.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList(growable: false),
    );
  }
}

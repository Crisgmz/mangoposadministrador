/// Cobro de suscripción con tarjeta (`azul_charges`) tal como lo devuelve la
/// RPC `admin_list_business_charges` (migración 0046): con sus reembolsos y
/// el saldo que todavía se puede devolver.
class SubscriptionCharge {
  const SubscriptionCharge({
    required this.id,
    required this.orderNumber,
    required this.attemptNumber,
    required this.amountCents,
    required this.status,
    required this.refundedCents,
    required this.pendingRefundCents,
    required this.refundableCents,
    required this.refunds,
    this.currencyCode = 'DOP',
    this.billingPeriodStart,
    this.billingPeriodEnd,
    this.responseMessage,
    this.errorDescription,
    this.authorizationCode,
    this.azulOrderId,
    this.attemptedAt,
    this.completedAt,
    this.cardBrand,
    this.cardMasked,
    this.currentPriceCents,
    this.azulSales = const [],
    this.ecfOverageCents = 0,
    this.ecfExtra = 0,
  });

  final String id;
  final String orderNumber;
  final int attemptNumber;
  final int amountCents;

  /// `pending | approved | declined | error | voided`.
  final String status;
  final String currencyCode;
  final DateTime? billingPeriodStart;
  final DateTime? billingPeriodEnd;
  final String? responseMessage;
  final String? errorDescription;
  final String? authorizationCode;
  final String? azulOrderId;
  final DateTime? attemptedAt;
  final DateTime? completedAt;
  final String? cardBrand;
  final String? cardMasked;

  /// Lo que costaría HOY ese período con la configuración actual (precio
  /// especial incluido). No es necesariamente lo que se debió cobrar: si el
  /// precio especial se cargó después del cobro, la diferencia es legítima.
  final int? currentPriceCents;

  /// Reembolsado y confirmado por Azul.
  final int refundedCents;

  /// Reembolsos con resultado desconocido: cuentan contra el saldo hasta que
  /// se verifiquen con Azul.
  final int pendingRefundCents;

  /// Lo que todavía se puede devolver (lo calcula el servidor).
  final int refundableCents;
  final List<ChargeRefund> refunds;

  /// Ventas que Azul aprobó para este cobro según la bitácora (migración
  /// 0048). Vacío si el servidor todavía no tiene 0048.
  ///
  /// Normalmente hay una. Más de una = el cliente pagó dos veces el mismo
  /// período: pasó en agosto 2026, cuando un reintento concurrente volvió a
  /// mandar la venta y pisó la primera respuesta en `azul_charges`.
  final List<AzulSale> azulSales;

  /// Parte del cobro que son facturas electrónicas extra (migración 0051).
  final int ecfOverageCents;

  /// Cuántas e-CF extra se cobraron.
  final int ecfExtra;

  bool get isApproved => status == 'approved';

  /// Azul aprobó más de una venta por este cobro.
  bool get isDuplicated => azulSales.length > 1;

  /// Lo que se cobró de más: el monto de cada venta repetida.
  int get duplicateCents =>
      isDuplicated ? amountCents * (azulSales.length - 1) : 0;

  /// Lo cobrado de más ya se devolvió.
  bool get duplicateResolved => isDuplicated && refundedCents >= duplicateCents;

  /// Cuánto falta devolver del duplicado, sin pasar del saldo reembolsable.
  int get duplicateOutstandingCents {
    if (!isDuplicated || duplicateResolved) return 0;
    final missing = duplicateCents - refundedCents;
    return missing < refundableCents ? missing : refundableCents;
  }

  bool get canRefund => refundableCents > 0;
  bool get fullyRefunded => isApproved && refundedCents >= amountCents;

  /// Cuánto se cobró por encima del precio actual del período, o null.
  int? get overPriceCents {
    final current = currentPriceCents;
    // Se compara solo la parte del plan: el extra de facturas electrónicas no
    // es un sobreprecio.
    final plan = amountCents - ecfOverageCents;
    if (!isApproved || current == null || plan <= current) return null;
    return plan - current;
  }

  String get cardLabel =>
      [cardBrand, cardMasked].whereType<String>().join(' ').trim();

  factory SubscriptionCharge.fromJson(Map<String, dynamic> json) {
    final card = json['card'] is Map
        ? Map<String, dynamic>.from(json['card'] as Map)
        : const <String, dynamic>{};
    final rawRefunds = json['refunds'];
    return SubscriptionCharge(
      id: json['id'] as String,
      orderNumber: (json['order_number'] as String?) ?? '',
      attemptNumber: _toInt(json['attempt_number']),
      amountCents: _toInt(json['amount_cents']),
      status: (json['status'] as String?) ?? 'pending',
      currencyCode: (json['currency_code'] as String?) ?? 'DOP',
      billingPeriodStart: _parseDate(json['billing_period_start']),
      billingPeriodEnd: _parseDate(json['billing_period_end']),
      responseMessage: json['response_message'] as String?,
      errorDescription: json['error_description'] as String?,
      authorizationCode: json['authorization_code'] as String?,
      azulOrderId: json['azul_order_id'] as String?,
      attemptedAt: _parseDate(json['attempted_at']),
      completedAt: _parseDate(json['completed_at']),
      cardBrand: card['brand'] as String?,
      cardMasked: card['masked'] as String?,
      currentPriceCents: json['current_price_cents'] == null
          ? null
          : _toInt(json['current_price_cents']),
      refundedCents: _toInt(json['refunded_cents']),
      pendingRefundCents: _toInt(json['pending_refund_cents']),
      refundableCents: _toInt(json['refundable_cents']),
      refunds: rawRefunds is List
          ? rawRefunds
                .whereType<Map>()
                .map((r) => ChargeRefund.fromJson(Map<String, dynamic>.from(r)))
                .toList(growable: false)
          : const [],
      ecfOverageCents: _toInt(json['ecf_overage_cents']),
      ecfExtra: json['ecf_detail'] is Map
          ? _toInt((json['ecf_detail'] as Map)['extra'])
          : 0,
      azulSales: json['azul_sales'] is List
          ? (json['azul_sales'] as List)
                .whereType<Map>()
                .map((s) => AzulSale.fromJson(Map<String, dynamic>.from(s)))
                .toList(growable: false)
          : const [],
    );
  }
}

/// Una venta aprobada por Azul (IsoCode 00) registrada en la bitácora.
class AzulSale {
  const AzulSale({this.azulOrderId, this.authorizationCode, this.approvedAt});

  final String? azulOrderId;
  final String? authorizationCode;
  final DateTime? approvedAt;

  factory AzulSale.fromJson(Map<String, dynamic> json) {
    return AzulSale(
      azulOrderId: json['azul_order_id'] as String?,
      authorizationCode: json['authorization_code'] as String?,
      approvedAt: _parseDate(json['approved_at']),
    );
  }
}

/// Reembolso de un cobro (`azul_refunds`).
class ChargeRefund {
  const ChargeRefund({
    required this.id,
    required this.amountCents,
    required this.status,
    required this.reason,
    this.requestedByEmail,
    this.requestedAt,
    this.completedAt,
    this.azulOrderId,
    this.responseMessage,
    this.errorDescription,
    this.resolutionNote,
  });

  final String id;
  final int amountCents;

  /// `pending | approved | declined | error`.
  final String status;
  final String reason;
  final String? requestedByEmail;
  final DateTime? requestedAt;
  final DateTime? completedAt;
  final String? azulOrderId;
  final String? responseMessage;
  final String? errorDescription;
  final String? resolutionNote;

  bool get isPending => status == 'pending';

  factory ChargeRefund.fromJson(Map<String, dynamic> json) {
    return ChargeRefund(
      id: json['id'] as String,
      amountCents: _toInt(json['amount_cents']),
      status: (json['status'] as String?) ?? 'pending',
      reason: (json['reason'] as String?) ?? '',
      requestedByEmail: json['requested_by_email'] as String?,
      requestedAt: _parseDate(json['requested_at']),
      completedAt: _parseDate(json['completed_at']),
      azulOrderId: json['azul_order_id'] as String?,
      responseMessage: json['response_message'] as String?,
      errorDescription: json['error_description'] as String?,
      resolutionNote: json['resolution_note'] as String?,
    );
  }
}

/// Resultado de pedir o verificar un reembolso (Edge Function
/// `admin-azul-refund`). `approved` = Azul confirmó la devolución.
class RefundActionResult {
  const RefundActionResult({
    required this.approved,
    required this.message,
    this.status,
  });

  final bool approved;
  final String message;

  /// Estado final del reembolso (`pending | approved | declined | error`).
  final String? status;
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

/// Tipo de prórroga / crédito otorgado por el operador.
enum ExtensionType { trialExtension, paymentGrace, freeCredit }

extension ExtensionTypeX on ExtensionType {
  static ExtensionType fromText(String? raw) {
    switch (raw) {
      case 'trial_extension':
        return ExtensionType.trialExtension;
      case 'payment_grace':
        return ExtensionType.paymentGrace;
      case 'free_credit':
        return ExtensionType.freeCredit;
      default:
        return ExtensionType.trialExtension;
    }
  }

  String get raw {
    switch (this) {
      case ExtensionType.trialExtension:
        return 'trial_extension';
      case ExtensionType.paymentGrace:
        return 'payment_grace';
      case ExtensionType.freeCredit:
        return 'free_credit';
    }
  }

  String get label {
    switch (this) {
      case ExtensionType.trialExtension:
        return 'Extensión de trial';
      case ExtensionType.paymentGrace:
        return 'Gracia de pago';
      case ExtensionType.freeCredit:
        return 'Crédito';
    }
  }
}

/// Fila de `admin_extensions` enriquecida con nombres del operador
/// (vía `get_business_extensions`).
class BusinessExtension {
  const BusinessExtension({
    required this.id,
    required this.businessId,
    required this.type,
    required this.reason,
    required this.grantedAt,
    this.daysGranted,
    this.amount,
    this.currencyCode,
    this.customerFacingMessage,
    this.effectiveUntil,
    this.previousEndDate,
    this.grantedByName,
    this.revertedAt,
    this.revertedByName,
    this.revertedReason,
    this.appliedToInvoiceId,
    this.appliedToInvoiceNumber,
  });

  final String id;
  final String businessId;
  final ExtensionType type;
  final String reason;
  final DateTime grantedAt;
  final int? daysGranted;
  final double? amount;
  final String? currencyCode;
  final String? customerFacingMessage;
  final DateTime? effectiveUntil;
  final DateTime? previousEndDate;
  final String? grantedByName;
  final DateTime? revertedAt;
  final String? revertedByName;
  final String? revertedReason;
  final String? appliedToInvoiceId;
  final String? appliedToInvoiceNumber;

  bool get isReverted => revertedAt != null;
  bool get isApplied => appliedToInvoiceId != null;
  bool get isActive => !isReverted && !isApplied;

  factory BusinessExtension.fromJson(Map<String, dynamic> json) {
    return BusinessExtension(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      type: ExtensionTypeX.fromText(json['extension_type'] as String?),
      reason: (json['reason'] as String?) ?? '',
      grantedAt: DateTime.parse(json['granted_at'] as String),
      daysGranted: _toInt(json['days_granted']),
      amount: _toDouble(json['amount']),
      currencyCode: json['currency_code'] as String?,
      customerFacingMessage: json['customer_facing_message'] as String?,
      effectiveUntil: _parseDate(json['effective_until']),
      previousEndDate: _parseDate(json['previous_end_date']),
      grantedByName: json['granted_by_name'] as String?,
      revertedAt: _parseDate(json['reverted_at']),
      revertedByName: json['reverted_by_name'] as String?,
      revertedReason: json['reverted_reason'] as String?,
      appliedToInvoiceId: json['applied_to_invoice_id'] as String?,
      appliedToInvoiceNumber: json['applied_to_invoice_number'] as String?,
    );
  }
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

int? _toInt(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}

double? _toDouble(dynamic raw) {
  if (raw == null) return null;
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}

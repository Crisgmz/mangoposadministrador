import '_json_helpers.dart';
import 'business_environment.dart';

enum InvoiceStatus { pending, paid, expired, voided }

extension InvoiceStatusX on InvoiceStatus {
  static InvoiceStatus fromText(String? raw) {
    switch (raw) {
      case 'paid':
        return InvoiceStatus.paid;
      case 'expired':
        return InvoiceStatus.expired;
      case 'void':
        return InvoiceStatus.voided;
      case 'pending':
      default:
        return InvoiceStatus.pending;
    }
  }

  String get label {
    switch (this) {
      case InvoiceStatus.pending:
        return 'Pendiente';
      case InvoiceStatus.paid:
        return 'Pagada';
      case InvoiceStatus.expired:
        return 'Vencida';
      case InvoiceStatus.voided:
        return 'Anulada';
    }
  }
}

/// Factura mensual de membresía. Mapea `membership_invoices` y la respuesta
/// de `get_billing_overview()` (que añade `business_name` y omite columnas
/// de auditoría como `voided_by`).
class MembershipInvoice {
  const MembershipInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.businessId,
    required this.businessName,
    required this.planType,
    required this.periodStart,
    required this.periodEnd,
    required this.issueDate,
    required this.dueDate,
    required this.amount,
    required this.itbis,
    required this.total,
    required this.status,
    this.paidAt,
    this.paymentMethod,
    this.paymentReference,
    required this.environment,
    this.ecfOverageAmount = 0,
    this.ecfExtra,
    this.ecfUnitPriceCents,
  });

  final String id;
  final String invoiceNumber;
  final String businessId;
  final String businessName;
  final String planType;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime issueDate;
  final DateTime dueDate;
  final double amount;
  final double itbis;
  final double total;
  final InvoiceStatus status;
  final DateTime? paidAt;
  final String? paymentMethod;
  final String? paymentReference;
  final BusinessEnvironment environment;

  /// Parte de [amount] que son facturas electrónicas extra (migración 0051).
  final double ecfOverageAmount;
  final int? ecfExtra;
  final int? ecfUnitPriceCents;

  factory MembershipInvoice.fromJson(Map<String, dynamic> json) {
    return MembershipInvoice(
      id: json['id'] as String,
      invoiceNumber: (json['invoice_number'] as String?) ?? '',
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      planType: (json['plan_type'] as String?) ?? 'unknown',
      periodStart: parseDate(json['period_start']) ?? DateTime.now(),
      periodEnd: parseDate(json['period_end']) ?? DateTime.now(),
      issueDate: parseDate(json['issue_date']) ?? DateTime.now(),
      dueDate: parseDate(json['due_date']) ?? DateTime.now(),
      amount: parseDouble(json['amount']),
      itbis: parseDouble(json['itbis']),
      total: parseDouble(json['total']),
      status: InvoiceStatusX.fromText(json['status'] as String?),
      paidAt: parseDate(json['paid_at']),
      paymentMethod: json['payment_method'] as String?,
      paymentReference: json['payment_reference'] as String?,
      environment: BusinessEnvironmentX.fromText(json['environment'] as String?),
      ecfOverageAmount: json['ecf_overage_amount'] == null
          ? 0
          : parseDouble(json['ecf_overage_amount']),
      ecfExtra: _ecfDetailInt(json['ecf_detail'], 'extra'),
      ecfUnitPriceCents: _ecfDetailInt(json['ecf_detail'], 'unit_price_cents'),
    );
  }
}

int? _ecfDetailInt(dynamic detail, String key) {
  if (detail is! Map) return null;
  final raw = detail[key];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return raw == null ? null : int.tryParse(raw.toString());
}

/// Métricas agregadas devueltas por `get_billing_metrics()`.
class BillingMetrics {
  const BillingMetrics({
    required this.mrr,
    required this.totalPaid,
    required this.totalPending,
    required this.totalExpired,
    required this.countPending,
    required this.countExpired,
  });

  final double mrr;
  final double totalPaid;
  final double totalPending;
  final double totalExpired;
  final int countPending;
  final int countExpired;

  factory BillingMetrics.fromJson(Map<String, dynamic> json) {
    return BillingMetrics(
      mrr: parseDouble(json['mrr']),
      totalPaid: parseDouble(json['total_paid']),
      totalPending: parseDouble(json['total_pending']),
      totalExpired: parseDouble(json['total_expired']),
      countPending: parseInt(json['count_pending']),
      countExpired: parseInt(json['count_expired']),
    );
  }
}

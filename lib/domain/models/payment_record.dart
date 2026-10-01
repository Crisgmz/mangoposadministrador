import 'business_environment.dart';
import 'membership_invoice.dart';

/// De dónde viene un pago.
enum PaymentKind {
  /// Cobro con tarjeta aprobado por Azul (`azul_charges`).
  card,

  /// Factura marcada pagada a mano (transferencia, efectivo, …).
  manual,
}

/// Un pago recibido de un negocio, tal como lo devuelve `admin_list_payments`
/// (migración 0049). Cada peso aparece una sola vez: una factura pagada por un
/// cobro con tarjeta sale como el cobro, no como pago manual.
class PaymentRecord {
  const PaymentRecord({
    required this.kind,
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.environment,
    required this.paidAt,
    required this.amountCents,
    required this.method,
    this.currencyCode = 'DOP',
    this.reference,
    this.periodStart,
    this.periodEnd,
    this.invoiceId,
    this.invoiceNumber,
    this.invoiceStatus,
    this.refundedCents = 0,
    this.salesCount = 0,
    this.cardLabel,
  });

  final PaymentKind kind;

  /// Id del cobro (tarjeta) o de la factura (manual).
  final String id;
  final String businessId;
  final String businessName;
  final BusinessEnvironment environment;
  final DateTime paidAt;
  final int amountCents;
  final String currencyCode;

  /// `card | transfer | cash | other`.
  final String method;

  /// AzulOrderId (tarjeta) o la referencia que cargó el operador (manual).
  final String? reference;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// Factura que quedó pagada con este pago. En tarjeta puede faltar: la
  /// conciliación automática no la encontró ni pudo crearla.
  final String? invoiceId;
  final String? invoiceNumber;
  final InvoiceStatus? invoiceStatus;

  /// Reembolsado de este cobro (solo tarjeta).
  final int refundedCents;

  /// Ventas aprobadas por Azul para este cobro (solo tarjeta). Más de una =
  /// el cliente pagó dos veces el mismo período.
  final int salesCount;
  final String? cardLabel;

  bool get isCard => kind == PaymentKind.card;

  /// Lo que efectivamente quedó cobrado: el monto menos lo reembolsado.
  int get netCents => amountCents - refundedCents;

  bool get isDuplicated => isCard && salesCount > 1;

  /// Pago con tarjeta que no dejó ninguna factura pagada.
  bool get missingInvoice => isCard && invoiceId == null;

  String get methodLabel => paymentMethodLabel(method);

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    return PaymentRecord(
      kind: json['kind'] == 'card' ? PaymentKind.card : PaymentKind.manual,
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      environment: BusinessEnvironmentX.fromText(
        json['environment'] as String?,
      ),
      paidAt: _parseDate(json['paid_at']) ?? DateTime.now(),
      amountCents: _toInt(json['amount_cents']),
      currencyCode: (json['currency_code'] as String?) ?? 'DOP',
      method: (json['method'] as String?) ?? 'other',
      reference: json['reference'] as String?,
      periodStart: _parseDate(json['period_start']),
      periodEnd: _parseDate(json['period_end']),
      invoiceId: json['invoice_id'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      invoiceStatus: json['invoice_status'] == null
          ? null
          : InvoiceStatusX.fromText(json['invoice_status'] as String?),
      refundedCents: _toInt(json['refunded_cents']),
      salesCount: _toInt(json['sales_count']),
      cardLabel: json['card_label'] as String?,
    );
  }
}

/// Etiqueta de un método de pago (mismos códigos que el diálogo de pago).
String paymentMethodLabel(String method) => switch (method) {
  'card' => 'Tarjeta',
  'transfer' => 'Transferencia',
  'cash' => 'Efectivo',
  'other' => 'Otro',
  _ => method,
};

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

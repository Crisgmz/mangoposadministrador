import '_json_helpers.dart';

/// Resultado de `admin_mark_invoices_paid` (migración 0044), tanto de la vista
/// previa como del pago real: el servidor corre la misma lógica en los dos.
class InvoicePaymentResult {
  const InvoicePaymentResult({
    required this.paid,
    required this.skipped,
    required this.moved,
    required this.dryRun,
  });

  /// Facturas que quedan pagadas (o quedarían, en vista previa).
  final List<PaidInvoice> paid;

  /// Facturas que no se tocan: ya pagadas, anuladas o inexistentes.
  final List<SkippedInvoice> skipped;

  /// Cobros con tarjeta que se corren porque la factura ya cubre ese período.
  final List<MovedCharge> moved;

  final bool dryRun;

  double get totalPaid => paid.fold<double>(0, (sum, p) => sum + p.total);

  factory InvoicePaymentResult.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> listOf(String key) =>
        ((json[key] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false);

    return InvoicePaymentResult(
      paid: listOf('paid').map(PaidInvoice.fromJson).toList(growable: false),
      skipped:
          listOf('skipped').map(SkippedInvoice.fromJson).toList(growable: false),
      moved: listOf('moved').map(MovedCharge.fromJson).toList(growable: false),
      dryRun: json['dry_run'] == true,
    );
  }
}

class PaidInvoice {
  const PaidInvoice({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.businessId,
    required this.businessName,
    required this.total,
  });

  final String invoiceId;
  final String invoiceNumber;
  final String businessId;
  final String businessName;
  final double total;

  factory PaidInvoice.fromJson(Map<String, dynamic> json) => PaidInvoice(
    invoiceId: json['invoice_id'] as String,
    invoiceNumber: (json['invoice_number'] as String?) ?? '—',
    businessId: json['business_id'] as String,
    businessName: (json['business_name'] as String?) ?? '—',
    total: parseDouble(json['total']),
  );
}

class SkippedInvoice {
  const SkippedInvoice({
    required this.invoiceId,
    required this.reason,
    this.invoiceNumber,
    this.businessName,
  });

  final String invoiceId;

  /// `paid | void | not_found` (o el estado en que estaba la factura).
  final String reason;
  final String? invoiceNumber;
  final String? businessName;

  String get reasonLabel => switch (reason) {
    'paid' => 'ya estaba pagada',
    'void' => 'está anulada',
    'not_found' => 'ya no existe',
    _ => reason,
  };

  factory SkippedInvoice.fromJson(Map<String, dynamic> json) => SkippedInvoice(
    invoiceId: json['invoice_id'] as String,
    reason: (json['reason'] as String?) ?? 'desconocido',
    invoiceNumber: json['invoice_number'] as String?,
    businessName: json['business_name'] as String?,
  );
}

/// Un próximo cobro con tarjeta que se corre al fin del período ya pagado.
class MovedCharge {
  const MovedCharge({
    required this.businessId,
    required this.businessName,
    required this.invoiceNumber,
    required this.from,
    required this.to,
    required this.wasPastDue,
  });

  final String businessId;
  final String businessName;
  final String invoiceNumber;
  final DateTime from;
  final DateTime to;

  /// Estaba atrasada: con este pago vuelve a activa y los intentos a 0.
  final bool wasPastDue;

  factory MovedCharge.fromJson(Map<String, dynamic> json) => MovedCharge(
    businessId: json['business_id'] as String,
    businessName: (json['business_name'] as String?) ?? '—',
    invoiceNumber: (json['invoice_number'] as String?) ?? '—',
    from: parseDate(json['from']) ?? DateTime.now(),
    to: parseDate(json['to']) ?? DateTime.now(),
    wasPastDue: json['was_past_due'] == true,
  );
}

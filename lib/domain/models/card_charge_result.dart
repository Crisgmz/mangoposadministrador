import 'invoice_payment_result.dart';

/// Cómo terminó un cobro de facturas a la tarjeta (Edge Function
/// `admin-azul-charge-invoices`, migración 0054).
enum CardChargeStatus {
  /// Azul aprobó: las facturas quedaron pagadas.
  approved,

  /// Azul rechazó la tarjeta: no se cobró nada.
  declined,

  /// Azul no lo procesó: no se cobró nada.
  error,

  /// No se sabe si Azul cobró: NO volver a cobrar, verificar.
  pending,
}

class CardChargeResult {
  const CardChargeResult({
    required this.status,
    required this.chargeId,
    this.message,
    this.amountCents,
    this.payment,
  });

  final CardChargeStatus status;
  final String chargeId;
  final String? message;
  final int? amountCents;

  /// Facturas pagadas / omitidas / cobros corridos, si Azul aprobó.
  final InvoicePaymentResult? payment;

  factory CardChargeResult.fromJson(Map<String, dynamic> json) {
    final status = switch (json['status']) {
      'approved' => CardChargeStatus.approved,
      'declined' => CardChargeStatus.declined,
      'error' => CardChargeStatus.error,
      _ => CardChargeStatus.pending,
    };
    final amount = json['amount_cents'];
    return CardChargeResult(
      status: status,
      chargeId: (json['charge_id'] ?? '').toString(),
      message: json['message'] as String?,
      amountCents: amount is num ? amount.toInt() : int.tryParse('${amount ?? ''}'),
      payment: json['paid'] is List
          ? InvoicePaymentResult.fromJson({
              'paid': json['paid'],
              'skipped': json['skipped'] ?? const [],
              'moved': json['moved'] ?? const [],
              'dry_run': false,
            })
          : null,
    );
  }
}

/// Error del cobro a la tarjeta con el código del servidor (charge_pending,
/// too_soon, invalid_charge…) y, si lo hay, el cobro al que se refiere.
class CardChargeException implements Exception {
  const CardChargeException(this.message, {this.code, this.chargeId});

  final String message;
  final String? code;
  final String? chargeId;

  @override
  String toString() => message;
}

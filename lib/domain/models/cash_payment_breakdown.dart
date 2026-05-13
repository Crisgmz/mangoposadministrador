import '_json_helpers.dart';

/// Una entrada del desglose de pagos por método dentro de una sesión de caja.
/// Mapea `get_cash_session_payment_breakdown`.
class CashPaymentBreakdownEntry {
  const CashPaymentBreakdownEntry({
    this.paymentMethodId,
    this.methodCode,
    this.methodName,
    required this.txnCount,
    required this.totalAmount,
    required this.pctOfTotal,
  });

  final String? paymentMethodId;
  final String? methodCode;
  final String? methodName;
  final int txnCount;
  final double totalAmount;
  final double pctOfTotal;

  /// Etiqueta humana: usa name → code → fallback.
  String get label {
    final name = methodName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final code = methodCode?.trim();
    if (code != null && code.isNotEmpty) return code;
    return 'Sin método';
  }

  /// Heurística: ¿este método representa efectivo (cash)? Sirve para
  /// resaltar la fila que sí afecta el saldo físico de la caja.
  bool get isCash {
    final c = (methodCode ?? '').toLowerCase();
    if (c.contains('cash') || c == 'efectivo' || c == 'ef') return true;
    final n = (methodName ?? '').toLowerCase();
    return n.contains('efectivo') || n.contains('cash');
  }

  factory CashPaymentBreakdownEntry.fromJson(Map<String, dynamic> json) {
    return CashPaymentBreakdownEntry(
      paymentMethodId: json['payment_method_id'] as String?,
      methodCode: json['method_code'] as String?,
      methodName: json['method_name'] as String?,
      txnCount: parseInt(json['txn_count']),
      totalAmount: parseDouble(json['total_amount']),
      pctOfTotal: parseDouble(json['pct_of_total']),
    );
  }
}

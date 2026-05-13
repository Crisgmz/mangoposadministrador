import '_json_helpers.dart';

/// Tipo de movimiento del kardex de caja. Los strings provienen del
/// enum implícito de `cash_transactions.type` en mangospos.
enum CashTxType { sale, deposit, withdrawal, expense, refund, other }

extension CashTxTypeX on CashTxType {
  static CashTxType fromText(String? raw) {
    switch (raw) {
      case 'sale':
        return CashTxType.sale;
      case 'deposit':
        return CashTxType.deposit;
      case 'withdrawal':
        return CashTxType.withdrawal;
      case 'expense':
        return CashTxType.expense;
      case 'refund':
        return CashTxType.refund;
      default:
        return CashTxType.other;
    }
  }

  String get label {
    switch (this) {
      case CashTxType.sale:
        return 'Venta';
      case CashTxType.deposit:
        return 'Depósito';
      case CashTxType.withdrawal:
        return 'Retiro';
      case CashTxType.expense:
        return 'Gasto';
      case CashTxType.refund:
        return 'Reembolso';
      case CashTxType.other:
        return 'Otro';
    }
  }

  /// `true` si el movimiento suma al saldo (sale/deposit), `false` si resta.
  bool get isInflow => this == CashTxType.sale || this == CashTxType.deposit;
}

/// Un movimiento del kardex de caja. Mapea `cash_transactions` filtrado
/// por la RPC `get_cash_session_kardex`.
class CashTransaction {
  const CashTransaction({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.amount,
    this.description,
    this.relatedOrderId,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final CashTxType type;
  final double amount;
  final String? description;
  final String? relatedOrderId;
  final DateTime createdAt;

  /// Monto firmado: positivo si entra, negativo si sale.
  double get signedAmount => type.isInflow ? amount : -amount;

  factory CashTransaction.fromJson(Map<String, dynamic> json) {
    return CashTransaction(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      type: CashTxTypeX.fromText(json['type'] as String?),
      amount: parseDouble(json['amount']),
      description: json['description'] as String?,
      relatedOrderId: json['related_order_id'] as String?,
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

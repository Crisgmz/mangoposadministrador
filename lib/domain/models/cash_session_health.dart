import '_json_helpers.dart';
import 'business_environment.dart';

enum CashSessionStatus { open, closed }

extension CashSessionStatusX on CashSessionStatus {
  static CashSessionStatus fromText(String? raw) {
    return raw == 'open' ? CashSessionStatus.open : CashSessionStatus.closed;
  }

  bool get isOpen => this == CashSessionStatus.open;
}

/// Una fila de salud de caja. Mapea `v_admin_cash_health` (RPC
/// `get_admin_cash_health`).
class CashSessionHealth {
  const CashSessionHealth({
    required this.sessionId,
    required this.businessId,
    required this.businessName,
    required this.environment,
    required this.cashRegisterId,
    required this.cajaNombre,
    this.userId,
    this.cashierName,
    required this.openedAt,
    this.closedAt,
    required this.status,
    required this.duracionSeconds,
    required this.startAmount,
    required this.ventasEfectivo,
    required this.depositos,
    required this.retiros,
    required this.gastos,
    required this.saldoEsperadoActual,
    this.endAmount,
    this.difference,
    required this.varianceFlagged,
    this.notes,
    required this.needsAttention,
  });

  final String sessionId;
  final String businessId;
  final String businessName;
  final BusinessEnvironment environment;
  final String cashRegisterId;
  final String cajaNombre;
  final String? userId;
  final String? cashierName;
  final DateTime openedAt;
  final DateTime? closedAt;
  final CashSessionStatus status;
  final int duracionSeconds;
  final double startAmount;
  final double ventasEfectivo;
  final double depositos;
  final double retiros;
  final double gastos;
  final double saldoEsperadoActual;
  final double? endAmount;
  final double? difference;
  final bool varianceFlagged;
  final String? notes;
  final bool needsAttention;

  Duration get duracion => Duration(seconds: duracionSeconds);
  bool get isOpen => status.isOpen;

  factory CashSessionHealth.fromJson(Map<String, dynamic> json) {
    return CashSessionHealth(
      sessionId: json['session_id'] as String,
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      environment:
          BusinessEnvironmentX.fromText(json['environment'] as String?),
      cashRegisterId: json['cash_register_id'] as String,
      cajaNombre: (json['caja_nombre'] as String?) ?? '—',
      userId: json['user_id'] as String?,
      cashierName: json['cashier_name'] as String?,
      openedAt: parseDate(json['opened_at']) ?? DateTime.now(),
      closedAt: parseDate(json['closed_at']),
      status: CashSessionStatusX.fromText(json['status'] as String?),
      duracionSeconds: parseInt(json['duracion_seconds']),
      startAmount: parseDouble(json['start_amount']),
      ventasEfectivo: parseDouble(json['ventas_efectivo']),
      depositos: parseDouble(json['depositos']),
      retiros: parseDouble(json['retiros']),
      gastos: parseDouble(json['gastos']),
      saldoEsperadoActual: parseDouble(json['saldo_esperado_actual']),
      endAmount: json['end_amount'] == null
          ? null
          : parseDouble(json['end_amount']),
      difference: json['difference'] == null
          ? null
          : parseDouble(json['difference']),
      varianceFlagged: json['variance_flagged'] == true,
      notes: json['notes'] as String?,
      needsAttention: json['needs_attention'] == true,
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../core/state/environment_filter.dart';
import '../../domain/models/cash_payment_breakdown.dart';
import '../../domain/models/cash_session_health.dart';
import '../../domain/models/cash_transaction.dart';

/// Filtros admitidos por `get_admin_cash_health` (RPC). Coinciden con los
/// strings que espera el backend.
enum CashHealthFilter { all, open, needsAttention, closedToday, varianceFlagged }

extension CashHealthFilterX on CashHealthFilter {
  String get raw {
    switch (this) {
      case CashHealthFilter.all:
        return 'all';
      case CashHealthFilter.open:
        return 'open';
      case CashHealthFilter.needsAttention:
        return 'needs_attention';
      case CashHealthFilter.closedToday:
        return 'closed_today';
      case CashHealthFilter.varianceFlagged:
        return 'variance_flagged';
    }
  }

  String get label {
    switch (this) {
      case CashHealthFilter.all:
        return 'Todas';
      case CashHealthFilter.open:
        return 'Abiertas';
      case CashHealthFilter.needsAttention:
        return 'Requieren atención';
      case CashHealthFilter.closedToday:
        return 'Cerradas hoy';
      case CashHealthFilter.varianceFlagged:
        return 'Con varianza';
    }
  }
}

class CashHealthRepository {
  CashHealthRepository(this._client);

  final SupabaseClient _client;

  Future<List<CashSessionHealth>> overview({
    String? businessId,
    CashHealthFilter filter = CashHealthFilter.all,
  }) async {
    final raw = await _client.rpc(
      'get_admin_cash_health',
      params: {
        'p_business_id': businessId,
        'p_filter': filter.raw,
      },
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(CashSessionHealth.fromJson)
        .toList(growable: false);
  }

  Future<CashSessionHealth?> detail(String sessionId) async {
    final raw = await _client.rpc(
      'get_cash_session_detail',
      params: {'p_session_id': sessionId},
    );
    if (raw == null || raw is! Map<String, dynamic>) return null;
    return CashSessionHealth.fromJson(raw);
  }

  Future<List<CashTransaction>> kardex(String sessionId) async {
    final raw = await _client.rpc(
      'get_cash_session_kardex',
      params: {'p_session_id': sessionId},
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(CashTransaction.fromJson)
        .toList(growable: false);
  }

  /// Desglose de pagos por método (efectivo, tarjeta, transferencia, etc.)
  /// dentro de una sesión de caja.
  Future<List<CashPaymentBreakdownEntry>> paymentBreakdown(
    String sessionId,
  ) async {
    final raw = await _client.rpc(
      'get_cash_session_payment_breakdown',
      params: {'p_session_id': sessionId},
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(CashPaymentBreakdownEntry.fromJson)
        .toList(growable: false);
  }

  Future<void> forceClose({
    required String sessionId,
    required double endAmount,
    required String reason,
  }) async {
    await _client.rpc(
      'admin_force_close_cash_session',
      params: {
        'p_session_id': sessionId,
        'p_end_amount': endAmount,
        'p_reason': reason,
      },
    );
  }
}

final cashHealthRepositoryProvider = Provider<CashHealthRepository>((ref) {
  return CashHealthRepository(ref.watch(supabaseProvider));
});

/// Args de la consulta: filtro + negocio seleccionado (puede ser null = todos).
class CashHealthQuery {
  const CashHealthQuery({required this.filter, this.businessId});

  final CashHealthFilter filter;
  final String? businessId;

  @override
  bool operator ==(Object other) =>
      other is CashHealthQuery &&
      other.filter == filter &&
      other.businessId == businessId;

  @override
  int get hashCode => Object.hash(filter, businessId);
}

/// Estado UI del filtrado de la pantalla de salud de cajas.
final cashHealthQueryProvider = StateProvider<CashHealthQuery>(
  (ref) => const CashHealthQuery(filter: CashHealthFilter.open),
);

/// Listado filtrado por el `CashHealthQuery` actual.
final cashHealthOverviewProvider =
    FutureProvider<List<CashSessionHealth>>((ref) async {
  final q = ref.watch(cashHealthQueryProvider);
  // Aunque el operador no aplique filtro de negocio, sí respetamos el
  // filtro global de entorno (prod/sandbox) que vive en `environmentFilterProvider`.
  final env = ref.watch(environmentFilterProvider);
  final rows = await ref.watch(cashHealthRepositoryProvider).overview(
        businessId: q.businessId,
        filter: q.filter,
      );
  if (env == null) return rows;
  return rows.where((s) => s.environment == env).toList(growable: false);
});

/// Detalle de una sesión por id.
final cashSessionDetailProvider =
    FutureProvider.family<CashSessionHealth?, String>((ref, id) {
  return ref.watch(cashHealthRepositoryProvider).detail(id);
});

/// Kardex de una sesión por id.
final cashSessionKardexProvider =
    FutureProvider.family<List<CashTransaction>, String>((ref, id) {
  return ref.watch(cashHealthRepositoryProvider).kardex(id);
});

/// Desglose de pagos por método (efectivo / tarjeta / transferencia / etc.)
/// para una sesión.
final cashSessionPaymentBreakdownProvider =
    FutureProvider.family<List<CashPaymentBreakdownEntry>, String>((ref, id) {
  return ref.watch(cashHealthRepositoryProvider).paymentBreakdown(id);
});

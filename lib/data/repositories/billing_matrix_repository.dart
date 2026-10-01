import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../core/state/environment_filter.dart';
import '../../domain/models/billing_matrix.dart';
import '../../domain/models/business_environment.dart';

/// Matriz de facturación negocio × mes. Un solo round-trip contra la RPC
/// `admin_billing_matrix` (migración 0042).
class BillingMatrixRepository {
  BillingMatrixRepository(this._client);

  final SupabaseClient _client;

  Future<List<BillingMatrixRow>> load({
    int months = 6,
    BusinessEnvironment? env,
  }) async {
    final raw = await _client.rpc(
      'admin_billing_matrix',
      params: {'p_months': months, 'p_env': env?.raw},
    );
    if (raw == null) return const [];
    return (raw as List<dynamic>)
        .map((r) => BillingMatrixRow.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }
}

final billingMatrixRepositoryProvider = Provider<BillingMatrixRepository>((ref) {
  return BillingMatrixRepository(ref.watch(supabaseProvider));
});

/// Tamaño de la ventana de meses que muestra la matriz. Default 6.
final billingMatrixMonthsProvider = StateProvider<int>((ref) => 6);

/// Filas de la matriz para el entorno y la ventana seleccionados.
final billingMatrixProvider = FutureProvider<List<BillingMatrixRow>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  final months = ref.watch(billingMatrixMonthsProvider);
  return ref
      .watch(billingMatrixRepositoryProvider)
      .load(months: months, env: env);
});

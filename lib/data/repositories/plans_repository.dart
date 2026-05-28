import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../domain/models/plan.dart';

/// Repositorio del catálogo de planes (RPCs en migración 0025).
class PlansRepository {
  PlansRepository(this._client);

  final SupabaseClient _client;

  Future<List<Plan>> list() async {
    final raw = await _client.rpc('admin_get_plans') as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(Plan.fromJson)
        .toList(growable: false);
  }

  /// Crea o actualiza un plan. `code` es la PK y no se modifica una vez creado.
  /// `taxIncluded=true` (default) significa que `priceMonthly` ya incluye ITBIS;
  /// la factura no desglosa impuesto. `false` agrega ITBIS sobre el precio.
  Future<void> upsert({
    required String code,
    required String name,
    String? description,
    required double priceMonthly,
    required List<String> features,
    required int displayOrder,
    bool isActive = true,
    bool taxIncluded = true,
  }) async {
    await _client.rpc(
      'admin_upsert_plan',
      params: {
        'p_code': code,
        'p_name': name,
        'p_description': description,
        'p_price_monthly': priceMonthly,
        'p_features': features,
        'p_display_order': displayOrder,
        'p_is_active': isActive,
        'p_tax_included': taxIncluded,
      },
    );
  }

  /// Soft-delete. Falla si hay suscriptores activos.
  Future<void> archive({required String code, required String reason}) async {
    await _client.rpc(
      'admin_archive_plan',
      params: {'p_code': code, 'p_reason': reason},
    );
  }

  Future<void> restore(String code) async {
    await _client.rpc('admin_restore_plan', params: {'p_code': code});
  }
}

final plansRepositoryProvider = Provider<PlansRepository>((ref) {
  return PlansRepository(ref.watch(supabaseProvider));
});

final plansListProvider = FutureProvider<List<Plan>>((ref) {
  return ref.watch(plansRepositoryProvider).list();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../domain/models/ecf_quota_usage.dart';

/// Facturas electrónicas incluidas por negocio y precio del extra
/// (migración 0051).
class EcfQuotaRepository {
  EcfQuotaRepository(this._client);

  final SupabaseClient _client;

  Future<EcfQuotaUsage> get(String businessId) async {
    final raw = await _client.rpc(
      'admin_get_ecf_usage',
      params: {'p_business_id': businessId},
    );
    return EcfQuotaUsage.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Fija (o cambia) la cantidad incluida. Sin [priceOverrideCents] usa el
  /// precio global. La primera vez, la cuenta arranca en este momento.
  Future<EcfQuotaUsage> set({
    required String businessId,
    required int included,
    int? priceOverrideCents,
    String? notes,
  }) async {
    final raw = await _client.rpc(
      'admin_set_ecf_quota',
      params: {
        'p_business_id': businessId,
        'p_included': included,
        'p_price_override_cents': priceOverrideCents,
        'p_notes': notes,
      },
    );
    return EcfQuotaUsage.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Quita la cantidad: las e-CF dejan de cobrarse aparte.
  Future<EcfQuotaUsage> clear(String businessId) async {
    final raw = await _client.rpc(
      'admin_clear_ecf_quota',
      params: {'p_business_id': businessId},
    );
    return EcfQuotaUsage.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Precio global por e-CF extra, en centavos.
  Future<int> setGlobalPrice(int priceCents) async {
    final raw = await _client.rpc(
      'admin_set_ecf_overage_price',
      params: {'p_price_cents': priceCents},
    );
    return raw is int ? raw : int.tryParse(raw.toString()) ?? priceCents;
  }
}

final ecfQuotaRepositoryProvider = Provider<EcfQuotaRepository>((ref) {
  return EcfQuotaRepository(ref.watch(supabaseProvider));
});

final ecfQuotaUsageProvider = FutureProvider.family<EcfQuotaUsage, String>((
  ref,
  businessId,
) {
  return ref.watch(ecfQuotaRepositoryProvider).get(businessId);
});

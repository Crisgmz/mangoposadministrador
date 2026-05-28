import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../domain/models/pending_business.dart';

class PendingAccountsQuery {
  const PendingAccountsQuery({
    this.search,
    this.onlyWithCard = false,
    this.limit = 50,
    this.offset = 0,
  });

  final String? search;
  final bool onlyWithCard;
  final int limit;
  final int offset;
}

class PendingAccountsRepository {
  PendingAccountsRepository(this._client);

  final SupabaseClient _client;

  Future<List<PendingBusiness>> list(PendingAccountsQuery q) async {
    final raw = await _client.rpc(
      'admin_list_pending_businesses',
      params: {
        'p_search': q.search,
        'p_only_with_card': q.onlyWithCard,
        'p_limit': q.limit,
        'p_offset': q.offset,
      },
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(PendingBusiness.fromJson)
        .toList(growable: false);
  }

  Future<int> count() async {
    final raw = await _client.rpc('admin_pending_count');
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// Aprueba (pending → active). Razón opcional.
  Future<void> approve({required String businessId, String? reason}) async {
    await _client.rpc(
      'admin_approve_pending_business',
      params: {
        'p_business_id': businessId,
        'p_reason': reason,
      },
    );
  }

  /// Rechaza (pending → inactive). Razón obligatoria (mínimo 10 chars).
  Future<void> reject({
    required String businessId,
    required String reason,
  }) async {
    await _client.rpc(
      'admin_reject_pending_business',
      params: {
        'p_business_id': businessId,
        'p_reason': reason,
      },
    );
  }
}

final pendingAccountsRepositoryProvider =
    Provider<PendingAccountsRepository>((ref) {
  return PendingAccountsRepository(ref.watch(supabaseProvider));
});

/// Query reactiva — busca y filtro de tarjeta. La página la actualiza.
final pendingAccountsQueryProvider =
    StateProvider<PendingAccountsQuery>((_) => const PendingAccountsQuery());

/// Lista paginada de cuentas pendientes.
final pendingAccountsListProvider =
    FutureProvider<List<PendingBusiness>>((ref) {
  final q = ref.watch(pendingAccountsQueryProvider);
  return ref.watch(pendingAccountsRepositoryProvider).list(q);
});

/// Contador global de cuentas pendientes — para el badge del sidebar.
final pendingAccountsCountProvider = FutureProvider<int>((ref) {
  return ref.watch(pendingAccountsRepositoryProvider).count();
});

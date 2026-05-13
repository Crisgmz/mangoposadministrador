import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../core/state/environment_filter.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/table_health.dart';

class TableHealthRepository {
  TableHealthRepository(this._client);

  final SupabaseClient _client;

  Future<TableHealthSummary> health({BusinessEnvironment? env}) async {
    final raw = await _client.rpc(
      'get_admin_table_health',
      params: {'p_env': env?.raw},
    ) as List<dynamic>;
    if (raw.isEmpty) {
      return const TableHealthSummary(
        zombieSessions: 0,
        stuckPayments: 0,
        orphanItems: 0,
        totalUnpaid: 0,
      );
    }
    return TableHealthSummary.fromJson(raw.first as Map<String, dynamic>);
  }

  Future<List<ZombieTableSession>> zombieSessions({
    BusinessEnvironment? env,
    String? businessId,
    int limit = 100,
  }) async {
    final raw = await _client.rpc(
      'get_admin_zombie_sessions',
      params: {
        'p_env': env?.raw,
        'p_business_id': businessId,
        'p_limit': limit,
      },
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(ZombieTableSession.fromJson)
        .toList(growable: false);
  }

  Future<List<StuckPayment>> stuckPayments({
    BusinessEnvironment? env,
    String? businessId,
    int limit = 100,
  }) async {
    final raw = await _client.rpc(
      'get_admin_stuck_payments',
      params: {
        'p_env': env?.raw,
        'p_business_id': businessId,
        'p_limit': limit,
      },
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(StuckPayment.fromJson)
        .toList(growable: false);
  }

  Future<List<OrphanOrderItem>> orphanItems({
    BusinessEnvironment? env,
    String? businessId,
    int limit = 200,
  }) async {
    final raw = await _client.rpc(
      'get_admin_orphan_items',
      params: {
        'p_env': env?.raw,
        'p_business_id': businessId,
        'p_limit': limit,
      },
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(OrphanOrderItem.fromJson)
        .toList(growable: false);
  }

  Future<void> closeZombieSession({
    required String sessionId,
    required String reason,
    bool voidOpenOrders = true,
  }) async {
    await _client.rpc(
      'admin_close_zombie_table_session',
      params: {
        'p_session_id': sessionId,
        'p_reason': reason,
        'p_void_open_orders': voidOpenOrders,
      },
    );
  }

  Future<void> voidOrphanItem({
    required String itemId,
    required String reason,
  }) async {
    await _client.rpc(
      'admin_void_orphan_item',
      params: {'p_item_id': itemId, 'p_reason': reason},
    );
  }
}

final tableHealthRepositoryProvider = Provider<TableHealthRepository>((ref) {
  return TableHealthRepository(ref.watch(supabaseProvider));
});

final tableHealthSummaryProvider = FutureProvider<TableHealthSummary>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(tableHealthRepositoryProvider).health(env: env);
});

final zombieSessionsProvider =
    FutureProvider<List<ZombieTableSession>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(tableHealthRepositoryProvider).zombieSessions(env: env);
});

final stuckPaymentsProvider = FutureProvider<List<StuckPayment>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(tableHealthRepositoryProvider).stuckPayments(env: env);
});

final orphanItemsProvider = FutureProvider<List<OrphanOrderItem>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(tableHealthRepositoryProvider).orphanItems(env: env);
});

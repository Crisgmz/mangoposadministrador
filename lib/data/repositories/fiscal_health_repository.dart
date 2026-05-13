import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../core/state/environment_filter.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/fiscal_health.dart';

class FiscalHealthRepository {
  FiscalHealthRepository(this._client);

  final SupabaseClient _client;

  Future<FiscalHealthSummary> health({BusinessEnvironment? env}) async {
    final raw = await _client.rpc(
      'get_admin_fiscal_health',
      params: {'p_env': env?.raw},
    ) as List<dynamic>;
    if (raw.isEmpty) {
      return const FiscalHealthSummary(
        ecfStuck: 0,
        ecfRejected24h: 0,
        ecfEmittedToday: 0,
        cancelledToday: 0,
        ncfSequencesTotal: 0,
        ncfCritical: 0,
        ncfWarning: 0,
        ncfExpiring: 0,
        ncfExpired: 0,
      );
    }
    return FiscalHealthSummary.fromJson(raw.first as Map<String, dynamic>);
  }

  Future<List<FiscalProblem>> problems({
    BusinessEnvironment? env,
    String? businessId,
    String kind = 'all',
    int limit = 100,
  }) async {
    final raw = await _client.rpc(
      'get_admin_fiscal_problems',
      params: {
        'p_env': env?.raw,
        'p_business_id': businessId,
        'p_kind': kind,
        'p_limit': limit,
      },
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(FiscalProblem.fromJson)
        .toList(growable: false);
  }

  Future<List<NcfSequenceStatus>> sequences({
    BusinessEnvironment? env,
    String statusFilter = 'all',
  }) async {
    final raw = await _client.rpc(
      'get_admin_ncf_sequences',
      params: {
        'p_env': env?.raw,
        'p_status_filter': statusFilter,
      },
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(NcfSequenceStatus.fromJson)
        .toList(growable: false);
  }

  Future<void> markEcfForRetry(String docId, {required String reason}) async {
    await _client.rpc(
      'admin_mark_ecf_for_retry',
      params: {'p_doc_id': docId, 'p_reason': reason},
    );
  }
}

final fiscalHealthRepositoryProvider = Provider<FiscalHealthRepository>((ref) {
  return FiscalHealthRepository(ref.watch(supabaseProvider));
});

/// Filtros UI de la página fiscal.
class FiscalProblemsQuery {
  const FiscalProblemsQuery({this.kind = 'all'});
  final String kind;

  FiscalProblemsQuery copyWith({String? kind}) =>
      FiscalProblemsQuery(kind: kind ?? this.kind);

  @override
  bool operator ==(Object other) =>
      other is FiscalProblemsQuery && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}

class NcfSequencesQuery {
  const NcfSequencesQuery({this.statusFilter = 'all'});
  final String statusFilter;

  NcfSequencesQuery copyWith({String? statusFilter}) =>
      NcfSequencesQuery(statusFilter: statusFilter ?? this.statusFilter);

  @override
  bool operator ==(Object other) =>
      other is NcfSequencesQuery && other.statusFilter == statusFilter;

  @override
  int get hashCode => statusFilter.hashCode;
}

final fiscalProblemsQueryProvider =
    StateProvider<FiscalProblemsQuery>((ref) => const FiscalProblemsQuery());

final ncfSequencesQueryProvider =
    StateProvider<NcfSequencesQuery>((ref) => const NcfSequencesQuery());

// --- Providers de lectura ---

final fiscalHealthSummaryProvider = FutureProvider<FiscalHealthSummary>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(fiscalHealthRepositoryProvider).health(env: env);
});

final fiscalProblemsProvider = FutureProvider<List<FiscalProblem>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  final q = ref.watch(fiscalProblemsQueryProvider);
  return ref.watch(fiscalHealthRepositoryProvider).problems(
        env: env,
        kind: q.kind,
      );
});

final ncfSequencesProvider = FutureProvider<List<NcfSequenceStatus>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  final q = ref.watch(ncfSequencesQueryProvider);
  return ref.watch(fiscalHealthRepositoryProvider).sequences(
        env: env,
        statusFilter: q.statusFilter,
      );
});

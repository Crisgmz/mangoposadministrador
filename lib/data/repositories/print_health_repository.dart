import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../core/state/environment_filter.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/print_agent_health.dart';
import '../../domain/models/print_job.dart';

class PrintHealthRepository {
  PrintHealthRepository(this._client);

  final SupabaseClient _client;

  Future<PrintHealthSummary> health() async {
    final raw = await _client.rpc('get_admin_print_health') as List<dynamic>;
    if (raw.isEmpty) {
      return const PrintHealthSummary(
        agentsTotal: 0,
        agentsOnline: 0,
        agentsLate: 0,
        agentsOffline: 0,
        jobsPending: 0,
        jobsPrinting: 0,
        jobsFailed1h: 0,
        jobsPrinted1h: 0,
      );
    }
    return PrintHealthSummary.fromJson(raw.first as Map<String, dynamic>);
  }

  Future<List<PrintAgentHealth>> agents({BusinessEnvironment? env}) async {
    final raw = await _client.rpc(
      'get_admin_print_agents',
      params: {'p_env': env?.raw},
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(PrintAgentHealth.fromJson)
        .toList(growable: false);
  }

  Future<List<PrintJob>> jobs({
    BusinessEnvironment? env,
    String? businessId,
    String statusFilter = 'non_terminal',
    int limit = 200,
  }) async {
    final raw = await _client.rpc(
      'get_admin_print_jobs',
      params: {
        'p_env': env?.raw,
        'p_business_id': businessId,
        'p_status_filter': statusFilter,
        'p_limit': limit,
      },
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(PrintJob.fromJson)
        .toList(growable: false);
  }

  Future<List<PrintFailureRanking>> topFailures({int limit = 10}) async {
    final raw = await _client.rpc(
      'get_admin_top_print_failures',
      params: {'p_limit': limit},
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(PrintFailureRanking.fromJson)
        .toList(growable: false);
  }

  Future<void> retryJob(String jobId, {String? reason}) async {
    await _client.rpc(
      'admin_retry_print_job',
      params: {'p_job_id': jobId, 'p_reason': reason},
    );
  }

  Future<void> cancelJob(String jobId, {required String reason}) async {
    await _client.rpc(
      'admin_cancel_print_job',
      params: {'p_job_id': jobId, 'p_reason': reason},
    );
  }
}

final printHealthRepositoryProvider = Provider<PrintHealthRepository>((ref) {
  return PrintHealthRepository(ref.watch(supabaseProvider));
});

/// Estado UI del filtro de la página de impresión (status filter + business).
class PrintJobsQuery {
  const PrintJobsQuery({this.statusFilter = 'non_terminal', this.businessId});

  final String statusFilter;
  final String? businessId;

  PrintJobsQuery copyWith({String? statusFilter, String? businessId, bool clearBusiness = false}) {
    return PrintJobsQuery(
      statusFilter: statusFilter ?? this.statusFilter,
      businessId: clearBusiness ? null : (businessId ?? this.businessId),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrintJobsQuery &&
      other.statusFilter == statusFilter &&
      other.businessId == businessId;

  @override
  int get hashCode => Object.hash(statusFilter, businessId);
}

final printJobsQueryProvider =
    StateProvider<PrintJobsQuery>((ref) => const PrintJobsQuery());

// --- Providers de lectura ---

final printHealthSummaryProvider = FutureProvider<PrintHealthSummary>((ref) {
  return ref.watch(printHealthRepositoryProvider).health();
});

final printAgentsProvider = FutureProvider<List<PrintAgentHealth>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(printHealthRepositoryProvider).agents(env: env);
});

final printJobsProvider = FutureProvider<List<PrintJob>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  final q = ref.watch(printJobsQueryProvider);
  return ref.watch(printHealthRepositoryProvider).jobs(
        env: env,
        businessId: q.businessId,
        statusFilter: q.statusFilter,
      );
});

final printTopFailuresProvider =
    FutureProvider<List<PrintFailureRanking>>((ref) {
  return ref.watch(printHealthRepositoryProvider).topFailures();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../core/state/environment_filter.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/noc_incident.dart';

class IncidentsRepository {
  IncidentsRepository(this._client);

  final SupabaseClient _client;

  Future<IncidentSummary> summary({BusinessEnvironment? env}) async {
    final raw = await _client.rpc(
      'get_admin_incident_summary',
      params: {'p_env': env?.raw},
    ) as List<dynamic>;
    if (raw.isEmpty) {
      return const IncidentSummary(
        openCritical: 0,
        openWarning: 0,
        openInfo: 0,
        openTotal: 0,
        closed24h: 0,
        oldestOpenSeconds: 0,
      );
    }
    return IncidentSummary.fromJson(raw.first as Map<String, dynamic>);
  }

  Future<List<NocIncident>> list({
    BusinessEnvironment? env,
    String status = 'all',
    String severity = 'all',
    int limit = 100,
  }) async {
    final raw = await _client.rpc(
      'get_admin_incidents',
      params: {
        'p_env': env?.raw,
        'p_status': status,
        'p_severity': severity,
        'p_limit': limit,
      },
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(NocIncident.fromJson)
        .toList(growable: false);
  }

  Future<int> activeCount({BusinessEnvironment? env}) async {
    final raw = await _client.rpc(
      'get_admin_active_incidents_count',
      params: {'p_env': env?.raw},
    );
    if (raw is int) return raw;
    return int.tryParse(raw.toString()) ?? 0;
  }

  Future<void> closeIncident(String id, {required String note}) async {
    await _client.rpc(
      'close_noc_incident',
      params: {'p_incident_id': id, 'p_note': note},
    );
  }

  Future<void> openManualIncident({
    required String type,
    required IncidentSeverity severity,
    String? businessId,
    String? title,
    String? description,
  }) async {
    await _client.rpc(
      'open_noc_incident',
      params: {
        'p_type': type,
        'p_severity': severity.raw,
        'p_business_id': businessId,
        'p_title': title,
        'p_description': description,
        'p_source': 'manual',
      },
    );
  }

  /// Ejecuta el scan de auto-detección. Devuelve cuántos se abrieron y cerraron.
  Future<({int opened, int closed})> runAutoDetection() async {
    final raw = await _client.rpc('noc_run_auto_detection') as List<dynamic>;
    if (raw.isEmpty) return (opened: 0, closed: 0);
    final m = raw.first as Map<String, dynamic>;
    final opened = m['opened_count'];
    final closed = m['closed_count'];
    return (
      opened: opened is int ? opened : int.tryParse('$opened') ?? 0,
      closed: closed is int ? closed : int.tryParse('$closed') ?? 0,
    );
  }
}

final incidentsRepositoryProvider = Provider<IncidentsRepository>((ref) {
  return IncidentsRepository(ref.watch(supabaseProvider));
});

/// Filtros UI.
class IncidentsQuery {
  const IncidentsQuery({this.status = 'open', this.severity = 'all'});
  final String status; // 'all' | 'open' | 'closed'
  final String severity; // 'all' | 'info' | 'warning' | 'critical'

  IncidentsQuery copyWith({String? status, String? severity}) =>
      IncidentsQuery(
        status: status ?? this.status,
        severity: severity ?? this.severity,
      );

  @override
  bool operator ==(Object other) =>
      other is IncidentsQuery &&
      other.status == status &&
      other.severity == severity;

  @override
  int get hashCode => Object.hash(status, severity);
}

final incidentsQueryProvider =
    StateProvider<IncidentsQuery>((ref) => const IncidentsQuery());

// Providers de lectura ------------------------------------------------------

final incidentSummaryProvider = FutureProvider<IncidentSummary>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(incidentsRepositoryProvider).summary(env: env);
});

final incidentsListProvider = FutureProvider<List<NocIncident>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  final q = ref.watch(incidentsQueryProvider);
  return ref.watch(incidentsRepositoryProvider).list(
        env: env,
        status: q.status,
        severity: q.severity,
      );
});

final activeIncidentsCountProvider = FutureProvider<int>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(incidentsRepositoryProvider).activeCount(env: env);
});

/// Lista de los críticos abiertos (subset corto, para el banner del dashboard).
final criticalOpenIncidentsProvider =
    FutureProvider<List<NocIncident>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(incidentsRepositoryProvider).list(
        env: env,
        status: 'open',
        severity: 'critical',
        limit: 20,
      );
});

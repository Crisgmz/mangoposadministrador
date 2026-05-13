import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../core/state/environment_filter.dart';
import '../../domain/models/audit_log_entry.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/business_overview.dart';
import '../../domain/models/business_week_trend.dart';
import '../../domain/models/platform_alert.dart';
import '../../domain/models/print_failure.dart';
import '../../domain/models/revenue_hour.dart';

/// Repositorio de la "Vista global". Delgado: cada método llama al RPC
/// correspondiente y mapea la respuesta a modelos de dominio.
class DashboardRepository {
  DashboardRepository(this._client);

  final SupabaseClient _client;

  Future<List<BusinessOverview>> overview() async {
    final raw = await _client.rpc('get_platform_overview') as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(BusinessOverview.fromJson)
        .toList(growable: false);
  }

  Future<List<RevenueHour>> revenueTrend12h({BusinessEnvironment? env}) async {
    final raw = await _client.rpc(
      'get_revenue_trend_12h',
      params: {'p_env': env?.raw},
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(RevenueHour.fromJson)
        .toList(growable: false);
  }

  Future<List<PlatformAlert>> alerts() async {
    final raw = await _client.rpc('get_platform_alerts') as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(PlatformAlert.fromJson)
        .toList(growable: false);
  }

  Future<List<AuditLogEntry>> criticalAuditLogs({
    String? businessId,
    int limit = 100,
  }) async {
    final raw = await _client.rpc(
      'get_critical_audit_logs',
      params: {
        'p_business_id': businessId,
        'p_limit': limit,
      },
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(AuditLogEntry.fromJson)
        .toList(growable: false);
  }

  Future<List<PrintFailure>> recentPrintFailures({
    String? businessId,
    int hours = 24,
    int limit = 100,
  }) async {
    final raw = await _client.rpc(
      'get_recent_print_failures',
      params: {
        'p_business_id': businessId,
        'p_hours': hours,
        'p_limit': limit,
      },
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(PrintFailure.fromJson)
        .toList(growable: false);
  }

  Future<List<BusinessWeekTrend>> businessWeekTrend() async {
    final raw = await _client.rpc('get_business_week_trend') as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(BusinessWeekTrend.fromJson)
        .toList(growable: false);
  }

  Future<void> toggleBusinessStatus(String businessId) async {
    await _client.rpc(
      'toggle_business_status',
      params: {'p_business_id': businessId},
    );
  }

  Future<void> setBusinessEnvironment(
    String businessId,
    BusinessEnvironment env,
  ) async {
    await _client.rpc(
      'set_business_environment',
      params: {'p_business_id': businessId, 'p_env': env.raw},
    );
  }

  /// Actualiza (o crea) la membresía del negocio:
  /// plan + fecha de corte + estado (active / expired / canceled).
  Future<void> updateBusinessMembership({
    required String businessId,
    required String planType,
    required DateTime endDate,
    required String status,
  }) async {
    await _client.rpc(
      'update_business_membership',
      params: {
        'p_business_id': businessId,
        'p_plan_type': planType,
        'p_end_date': endDate.toUtc().toIso8601String(),
        'p_status': status,
      },
    );
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(supabaseProvider));
});

/// Listado crudo de negocios con métricas (sin filtro de entorno).
final platformOverviewProvider = FutureProvider<List<BusinessOverview>>((ref) {
  return ref.watch(dashboardRepositoryProvider).overview();
});

/// Listado **filtrado** por el entorno seleccionado en `environmentFilterProvider`.
/// Es el provider que las pantallas deberían consumir.
final filteredOverviewProvider = Provider<AsyncValue<List<BusinessOverview>>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(platformOverviewProvider).whenData((rows) {
    if (env == null) return rows;
    return rows.where((b) => b.environment == env).toList(growable: false);
  });
});

/// Tendencia de ingresos plataforma últimas 12 horas. Server-side filtra por env.
final revenueTrend12hProvider = FutureProvider<List<RevenueHour>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(dashboardRepositoryProvider).revenueTrend12h(env: env);
});

/// Lista cruda de alertas activas.
final platformAlertsProvider = FutureProvider<List<PlatformAlert>>((ref) {
  return ref.watch(dashboardRepositoryProvider).alerts();
});

/// Alertas filtradas por entorno seleccionado.
final filteredAlertsProvider = Provider<AsyncValue<List<PlatformAlert>>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(platformAlertsProvider).whenData((rows) {
    if (env == null) return rows;
    return rows.where((a) => a.environment == env).toList(growable: false);
  });
});

/// Auditoría plataforma. `businessId` opcional para filtrar a un negocio.
final criticalAuditLogsProvider =
    FutureProvider.family<List<AuditLogEntry>, String?>((ref, businessId) {
  return ref
      .watch(dashboardRepositoryProvider)
      .criticalAuditLogs(businessId: businessId);
});

/// Auditoría filtrada por entorno y por negocio.
final filteredAuditLogsProvider = Provider.family<
    AsyncValue<List<AuditLogEntry>>, String?>((ref, businessId) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(criticalAuditLogsProvider(businessId)).whenData((rows) {
    if (env == null) return rows;
    return rows.where((l) => l.environment == env).toList(growable: false);
  });
});

/// Fallas de impresión recientes. `businessId` opcional.
final recentPrintFailuresProvider =
    FutureProvider.family<List<PrintFailure>, String?>((ref, businessId) {
  return ref
      .watch(dashboardRepositoryProvider)
      .recentPrintFailures(businessId: businessId);
});

/// Fallas filtradas por entorno y negocio.
final filteredPrintFailuresProvider = Provider.family<
    AsyncValue<List<PrintFailure>>, String?>((ref, businessId) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(recentPrintFailuresProvider(businessId)).whenData((rows) {
    if (env == null) return rows;
    return rows.where((f) => f.environment == env).toList(growable: false);
  });
});

/// Tendencia semanal de ingresos por negocio (sin filtrar).
final businessWeekTrendProvider = FutureProvider<List<BusinessWeekTrend>>((ref) {
  return ref.watch(dashboardRepositoryProvider).businessWeekTrend();
});

/// Tendencia semanal filtrada por entorno.
final filteredWeekTrendProvider =
    Provider<AsyncValue<List<BusinessWeekTrend>>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  return ref.watch(businessWeekTrendProvider).whenData((rows) {
    if (env == null) return rows;
    return rows.where((t) => t.environment == env).toList(growable: false);
  });
});

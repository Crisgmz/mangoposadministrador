import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../core/state/environment_filter.dart';
import '../../domain/models/audit_log_entry.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/business_extension.dart';
import '../../domain/models/business_member.dart';
import '../../domain/models/business_overview.dart';
import '../../domain/models/business_week_trend.dart';
import '../../domain/models/customer_note.dart';
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

  /// Desactiva el negocio (status='inactive') con razón obligatoria.
  Future<void> deactivateBusiness(String businessId, String reason) async {
    await _client.rpc(
      'deactivate_business',
      params: {'p_business_id': businessId, 'p_reason': reason},
    );
  }

  /// Reactiva el negocio (status='active'). Razón opcional.
  Future<void> activateBusiness(String businessId, {String? reason}) async {
    await _client.rpc(
      'activate_business',
      params: {'p_business_id': businessId, 'p_reason': reason},
    );
  }

  /// Borra permanentemente el negocio. Requiere confirmación tipada con el
  /// nombre exacto del negocio y razón. La RPC valida ambos.
  ///
  /// [force] activa el bypass de triggers user-defined (`session_replication_role
  /// = replica`) para vencer protectores tipo "cash_count_blind is immutable
  /// after signing". Usar solo cuando el negocio tenga sesiones firmadas o
  /// data fiscal protegida que impide el borrado normal. El audit registra
  /// que se forzó.
  Future<void> deleteBusiness({
    required String businessId,
    required String confirmation,
    required String reason,
    bool force = false,
  }) async {
    await _client.rpc(
      'delete_business',
      params: {
        'p_business_id': businessId,
        'p_confirmation': confirmation,
        'p_reason': reason,
        'p_force': force,
      },
    );
  }

  /// Onboarding manual de un nuevo negocio. El owner debe existir como
  /// usuario en `auth.users` (registro público previo). Devuelve el id del
  /// negocio creado.
  Future<String> createBusiness({
    required String ownerEmail,
    required String businessName,
    String? businessType,
    String? domain,
    required String environment, // 'production' | 'sandbox'
    required String planType, // 'trial' | 'free' | 'basic' | 'pro'
    int trialDays = 30,
  }) async {
    final raw = await _client.rpc(
      'admin_create_business',
      params: {
        'p_owner_email': ownerEmail,
        'p_business_name': businessName,
        'p_business_type': businessType,
        'p_domain': domain,
        'p_environment': environment,
        'p_plan_type': planType,
        'p_trial_days': trialDays,
      },
    );
    if (raw is List && raw.isNotEmpty) {
      final row = raw.first as Map<String, dynamic>;
      return row['business_id'] as String;
    }
    if (raw is Map<String, dynamic>) {
      return raw['business_id'] as String;
    }
    throw StateError('admin_create_business: respuesta inesperada $raw');
  }

  /// Histórico de prórrogas / créditos del negocio.
  Future<List<BusinessExtension>> getBusinessExtensions(
    String businessId,
  ) async {
    final raw = await _client.rpc(
      'get_business_extensions',
      params: {'p_business_id': businessId},
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(BusinessExtension.fromJson)
        .toList(growable: false);
  }

  /// Otorga una prórroga (trial / gracia) o crédito.
  ///
  /// - `trial_extension` y `payment_grace`: `days` requerido, `amount` null.
  /// - `free_credit`: `amount` requerido, `days` null.
  Future<void> grantExtension({
    required String businessId,
    required ExtensionType type,
    int? days,
    double? amount,
    required String reason,
    String? customerMessage,
  }) async {
    await _client.rpc(
      'grant_extension',
      params: {
        'p_business_id': businessId,
        'p_type': type.raw,
        'p_days': days,
        'p_amount': amount,
        'p_reason': reason,
        'p_customer_msg': customerMessage,
      },
    );
  }

  /// Revierte una prórroga ya otorgada. Restaura `end_date` si aplica.
  Future<void> revertExtension({
    required String extensionId,
    required String reason,
  }) async {
    await _client.rpc(
      'revert_extension',
      params: {'p_extension_id': extensionId, 'p_reason': reason},
    );
  }

  /// Notas internas (CRM) del negocio. Pinned primero, luego más recientes.
  Future<List<CustomerNote>> getCustomerNotes(String businessId) async {
    final raw = await _client.rpc(
      'get_customer_notes',
      params: {'p_business_id': businessId},
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(CustomerNote.fromJson)
        .toList(growable: false);
  }

  Future<void> createCustomerNote({
    required String businessId,
    required NoteCategory category,
    required String body,
    bool pinned = false,
  }) async {
    await _client.rpc(
      'create_customer_note',
      params: {
        'p_business_id': businessId,
        'p_category': category.raw,
        'p_body': body,
        'p_pinned': pinned,
      },
    );
  }

  /// Solo el autor puede editar. La RPC valida y devuelve error si no.
  Future<void> updateCustomerNote({
    required String noteId,
    required NoteCategory category,
    required String body,
    required bool pinned,
  }) async {
    await _client.rpc(
      'update_customer_note',
      params: {
        'p_note_id': noteId,
        'p_category': category.raw,
        'p_body': body,
        'p_pinned': pinned,
      },
    );
  }

  /// Cualquier operador puede fijar/desfijar (no requiere ser autor).
  Future<void> toggleCustomerNotePin(String noteId) async {
    await _client.rpc(
      'toggle_customer_note_pin',
      params: {'p_note_id': noteId},
    );
  }

  /// Solo el autor puede borrar.
  Future<void> deleteCustomerNote(String noteId) async {
    await _client.rpc(
      'delete_customer_note',
      params: {'p_note_id': noteId},
    );
  }

  /// Owner + miembros del negocio con email, nombre, teléfono y fechas
  /// (último login, alta del usuario). Owner siempre primero.
  Future<List<BusinessMember>> getBusinessTeam(String businessId) async {
    final raw = await _client.rpc(
      'admin_get_business_team',
      params: {'p_business_id': businessId},
    ) as List<dynamic>;
    return raw
        .cast<Map<String, dynamic>>()
        .map(BusinessMember.fromJson)
        .toList(growable: false);
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

/// Filtro de status para la tabla de negocios. `null` = todos. Valores
/// posibles: 'active', 'pending', 'inactive'.
final businessStatusFilterProvider = StateProvider<String?>((_) => null);

/// Listado **filtrado** por el entorno seleccionado en `environmentFilterProvider`
/// y el status seleccionado en `businessStatusFilterProvider`.
/// Es el provider que las pantallas deberían consumir.
final filteredOverviewProvider = Provider<AsyncValue<List<BusinessOverview>>>((ref) {
  final env = ref.watch(environmentFilterProvider);
  final statusFilter = ref.watch(businessStatusFilterProvider);
  return ref.watch(platformOverviewProvider).whenData((rows) {
    Iterable<BusinessOverview> out = rows;
    if (env != null) {
      out = out.where((b) => b.environment == env);
    }
    if (statusFilter != null) {
      out = out.where((b) => b.status == statusFilter);
    }
    return out.toList(growable: false);
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

/// Histórico de prórrogas / créditos otorgados por el operador.
final businessExtensionsProvider =
    FutureProvider.family<List<BusinessExtension>, String>((ref, businessId) {
  return ref
      .watch(dashboardRepositoryProvider)
      .getBusinessExtensions(businessId);
});

/// Notas internas (CRM) del negocio.
final customerNotesProvider =
    FutureProvider.family<List<CustomerNote>, String>((ref, businessId) {
  return ref.watch(dashboardRepositoryProvider).getCustomerNotes(businessId);
});

/// Owner + miembros del negocio (datos de contacto).
final businessTeamProvider =
    FutureProvider.family<List<BusinessMember>, String>((ref, businessId) {
  return ref.watch(dashboardRepositoryProvider).getBusinessTeam(businessId);
});

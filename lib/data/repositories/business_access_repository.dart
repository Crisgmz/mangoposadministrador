import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../domain/models/business_access.dart';

/// Control del bloqueo del POS por falta de pago (migración 0040).
///
/// Todo pasa por RPCs `security definer` gateadas por `is_platform_operator()`
/// y auditadas en `noc_audit_log` con razón obligatoria. El motor de estado
/// vive en la BD (`fn_business_access_state`), así que el panel y el POS
/// siempre ven exactamente lo mismo.
class BusinessAccessRepository {
  BusinessAccessRepository(this._client);

  final SupabaseClient _client;

  Future<BusinessAccess?> get(String businessId) async {
    final raw = await _client.rpc(
      'admin_get_business_access',
      params: {'p_business_id': businessId},
    );
    if (raw == null) return null;
    return BusinessAccess.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Corta el acceso al POS de inmediato. Limpia cualquier prórroga vigente.
  Future<BusinessAccess?> lock({
    required String businessId,
    required String reason,
    String? customerMessage,
    String? contactName,
    String? contactPhone,
  }) {
    return _set(
      businessId: businessId,
      action: 'lock',
      reason: reason,
      customerMessage: customerMessage,
      contactName: contactName,
      contactPhone: contactPhone,
    );
  }

  /// Devuelve el negocio a modo automático y quita el corte programado.
  ///
  /// OJO: si su `billing_status` sigue en suspended/past_due vencido, el POS
  /// se vuelve a bloquear solo. Para garantizar acceso mientras se regulariza
  /// el pago, usa [extend].
  Future<BusinessAccess?> unlock({
    required String businessId,
    required String reason,
  }) {
    return _set(businessId: businessId, action: 'unlock', reason: reason);
  }

  /// Programa el corte para una fecha futura. El POS muestra la regresiva.
  Future<BusinessAccess?> schedule({
    required String businessId,
    required String reason,
    required DateTime lockAt,
    String? customerMessage,
  }) {
    return _set(
      businessId: businessId,
      action: 'schedule',
      reason: reason,
      scheduledLockAt: lockAt,
      customerMessage: customerMessage,
    );
  }

  /// Prórroga: acceso garantizado hasta [until] aunque el billing diga lo
  /// contrario. Al vencer, el estado vuelve a calcularse solo.
  Future<BusinessAccess?> extend({
    required String businessId,
    required String reason,
    required DateTime until,
    String? customerMessage,
  }) {
    return _set(
      businessId: businessId,
      action: 'extend',
      reason: reason,
      overrideUntil: until,
      customerMessage: customerMessage,
    );
  }

  /// Solo edita mensaje/contacto/gracia/enforcement, sin cambiar el modo.
  Future<BusinessAccess?> update({
    required String businessId,
    required String reason,
    String? customerMessage,
    bool clearMessage = false,
    String? contactName,
    String? contactPhone,
    int? graceDays,
    String? enforcement,
  }) {
    return _set(
      businessId: businessId,
      action: 'update',
      reason: reason,
      customerMessage: customerMessage,
      clearMessage: clearMessage,
      contactName: contactName,
      contactPhone: contactPhone,
      graceDays: graceDays,
      enforcement: enforcement,
    );
  }

  Future<BusinessAccess?> _set({
    required String businessId,
    required String action,
    required String reason,
    String? customerMessage,
    DateTime? scheduledLockAt,
    DateTime? overrideUntil,
    int? graceDays,
    String? enforcement,
    String? contactName,
    String? contactPhone,
    bool clearSchedule = false,
    bool clearOverride = false,
    bool clearMessage = false,
  }) async {
    final raw = await _client.rpc(
      'admin_set_business_access',
      params: {
        'p_business_id': businessId,
        'p_action': action,
        'p_reason': reason,
        'p_customer_message': customerMessage,
        'p_scheduled_lock_at': scheduledLockAt?.toUtc().toIso8601String(),
        'p_override_until': overrideUntil?.toUtc().toIso8601String(),
        'p_grace_days': graceDays,
        'p_enforcement': enforcement,
        'p_contact_name': contactName,
        'p_contact_phone': contactPhone,
        'p_clear_schedule': clearSchedule,
        'p_clear_override': clearOverride,
        'p_clear_message': clearMessage,
      },
    );
    if (raw == null) return null;
    return BusinessAccess.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  // ---------------------------------------------------------------------------
  // Política global
  // ---------------------------------------------------------------------------

  Future<AccessPolicy?> getPolicy() async {
    final raw = await _client.rpc('admin_get_access_policy');
    if (raw == null) return null;
    return AccessPolicy.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<AccessPolicy?> setPolicy({
    required String reason,
    bool? enforcementEnabled,
    int? defaultGraceDays,
    bool? lockOnPastDue,
    bool? lockOnTrialExpired,
    int? offlineMaxDays,
    String? defaultCustomerMessage,
    String? contactName,
    String? contactPhone,
    String? contactEmail,
  }) async {
    final raw = await _client.rpc(
      'admin_set_access_policy',
      params: {
        'p_reason': reason,
        'p_enforcement_enabled': enforcementEnabled,
        'p_default_grace_days': defaultGraceDays,
        'p_lock_on_past_due': lockOnPastDue,
        'p_lock_on_trial_expired': lockOnTrialExpired,
        'p_offline_max_days': offlineMaxDays,
        'p_default_customer_message': defaultCustomerMessage,
        'p_contact_name': contactName,
        'p_contact_phone': contactPhone,
        'p_contact_email': contactEmail,
      },
    );
    if (raw == null) return null;
    return AccessPolicy.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Negocios que no están 'ok' — cartera de cobranza.
  Future<List<AffectedBusiness>> listAffected() async {
    final rows = await _client.rpc(
      'admin_list_locked_businesses',
      params: {'p_include_ok': false},
    );
    if (rows is! List) return const [];
    return rows
        .map((r) => AffectedBusiness.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }
}

final businessAccessRepositoryProvider = Provider<BusinessAccessRepository>(
  (ref) => BusinessAccessRepository(ref.watch(supabaseProvider)),
);

/// Estado de acceso por negocio (family por businessId).
final businessAccessProvider =
    FutureProvider.family<BusinessAccess?, String>((ref, businessId) {
  return ref.watch(businessAccessRepositoryProvider).get(businessId);
});

/// Política global del bloqueo.
final accessPolicyProvider = FutureProvider<AccessPolicy?>((ref) {
  return ref.watch(businessAccessRepositoryProvider).getPolicy();
});

/// Cartera: negocios bloqueados, en gracia o con aviso.
final affectedBusinessesProvider =
    FutureProvider<List<AffectedBusiness>>((ref) {
  return ref.watch(businessAccessRepositoryProvider).listAffected();
});

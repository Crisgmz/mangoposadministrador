import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../domain/models/ecf_onboarding.dart';

/// Alta de facturación electrónica por negocio. Todo pasa por dos Edge
/// Functions del repo mangospos:
///   - `ecf-onboarding`: datos, empresa en Alanube, secuencias y modalidad.
///     Valida `is_platform_operator()` y audita en `noc_audit_log`.
///   - `provision-ecf`: preflight y activación (`business_alanube_settings`).
class EcfOnboardingRepository {
  EcfOnboardingRepository(this._client);

  final SupabaseClient _client;

  Future<EcfOnboardingStatus> status(String businessId) async {
    final data = await _onboarding('status', businessId);
    return EcfOnboardingStatus.fromJson(data);
  }

  Future<void> saveData(String businessId, EcfTaxpayerDraft draft) async {
    await _onboarding('save_data', businessId, {'data': draft.toJson()});
  }

  /// Copia RNC y razón social del borrador a `fiscal_settings` (lo que usa la
  /// POS y lo que compara el preflight).
  Future<void> syncFiscal(String businessId) async {
    await _onboarding('sync_fiscal', businessId);
  }

  /// Empresas asociadas en Alanube con el RNC del negocio.
  Future<List<EcfCompany>> findCompany(String businessId) async {
    final data = await _onboarding('find_company', businessId);
    return ((data['matches'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => EcfCompany.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<void> linkCompany(String businessId, String alanubeCompanyId) async {
    await _onboarding('link_company', businessId, {
      'alanube_company_id': alanubeCompanyId,
    });
  }

  /// Da de alta la empresa en Alanube. El certificado y la contraseña viajan
  /// solo en esta petición: el servidor no los guarda.
  Future<EcfCompany?> registerCompany({
    required String businessId,
    required String certificateFilename,
    required Uint8List certificateBytes,
    required String certificatePassword,
  }) async {
    final data = await _onboarding('register_company', businessId, {
      'certificate': {
        'filename': certificateFilename,
        'content_base64': base64Encode(certificateBytes),
        'password': certificatePassword,
      },
    });
    final company = data['company'];
    return company is Map
        ? EcfCompany.fromJson(Map<String, dynamic>.from(company))
        : null;
  }

  Future<void> saveSequence({
    required String businessId,
    required String ncfType,
    required int rangeStart,
    required int rangeEnd,
    DateTime? expirationDate,
    String? authorizationNumber,
    int? lastUsed,
  }) async {
    await _onboarding('save_sequence', businessId, {
      'sequence': {
        'ncf_type': ncfType,
        'range_start': rangeStart,
        'range_end': rangeEnd,
        'expiration_date': expirationDate == null
            ? null
            : '${expirationDate.year.toString().padLeft(4, '0')}-'
                '${expirationDate.month.toString().padLeft(2, '0')}-'
                '${expirationDate.day.toString().padLeft(2, '0')}',
        'authorization_number': authorizationNumber,
        'last_used': lastUsed,
      },
    });
  }

  Future<void> setEcfEnabled(String businessId, bool enabled) async {
    await _onboarding('set_ecf_enabled', businessId, {'enabled': enabled});
  }

  /// Solicitudes que hicieron los clientes desde la POS, las más nuevas primero.
  Future<List<EcfRequestSummary>> listRequests() async {
    try {
      final res = await _client.functions.invoke('ecf-onboarding', body: {
        'action': 'list_requests',
      });
      final data = _asMap(res.data);
      return ((data['requests'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfRequestSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on FunctionException catch (e) {
      throw EcfOnboardingException.from(e);
    }
  }

  // ---- Certificación ante la DGII ----------------------------------------

  Future<EcfPostulationInfo> postulationInfo(String businessId) async {
    final data = await _onboarding('postulation_info', businessId);
    return EcfPostulationInfo.fromJson(data);
  }

  /// Alanube firma el XML con el certificado de la empresa y devuelve el
  /// enlace del XML firmado, que es lo que se sube a la OFV.
  Future<String> signDocument({
    required String businessId,
    required EcfSignKind kind,
    required String filename,
    required Uint8List bytes,
  }) async {
    final data = await _onboarding('sign_document', businessId, {
      'kind': kind.code,
      'xml': {'filename': filename, 'content_base64': base64Encode(bytes)},
    });
    final url = data['signed_document_url'];
    if (url is! String || url.isEmpty) {
      throw const EcfOnboardingException('El servidor no devolvió el XML firmado.');
    }
    return url;
  }

  Future<EcfSetTest?> createSetTest(String businessId, EcfItemExample item) async {
    final data = await _onboarding('create_set_test', businessId, {
      'item_example': item.toJson(),
    });
    final t = data['set_test'];
    return t is Map ? EcfSetTest.fromJson(Map<String, dynamic>.from(t)) : null;
  }

  Future<EcfSetTest?> checkSetTest(String businessId) async {
    final data = await _onboarding('check_set_test', businessId);
    final t = data['set_test'];
    return t is Map ? EcfSetTest.fromJson(Map<String, dynamic>.from(t)) : null;
  }

  Future<void> setDgiiAuthorized(String businessId, bool authorized) async {
    await _onboarding('set_dgii_authorized', businessId, {'authorized': authorized});
  }

  /// Preflight de `provision-ecf`. Con [dryRun] en false, si no hay chequeos
  /// en rojo escribe `business_alanube_settings` y el negocio queda listo para
  /// encender la modalidad e-CF.
  Future<EcfPreflightResult> provision({
    required String businessId,
    required String alanubeCompanyId,
    required bool dryRun,
  }) async {
    try {
      final res = await _client.functions.invoke('provision-ecf', body: {
        'business_id': businessId,
        'alanube_company_id': alanubeCompanyId,
        'dry_run': dryRun,
      });
      return EcfPreflightResult.fromJson(_asMap(res.data));
    } on FunctionException catch (e) {
      // 409 preflight_failed trae el semáforo: es un resultado, no un error.
      final details = e.details;
      if (details is Map && details['checks'] is List) {
        return EcfPreflightResult.fromJson(Map<String, dynamic>.from(details));
      }
      throw EcfOnboardingException.from(e);
    }
  }

  Future<Map<String, dynamic>> _onboarding(
    String action,
    String businessId, [
    Map<String, dynamic> params = const {},
  ]) async {
    try {
      final res = await _client.functions.invoke('ecf-onboarding', body: {
        'action': action,
        'business_id': businessId,
        ...params,
      });
      return _asMap(res.data);
    } on FunctionException catch (e) {
      throw EcfOnboardingException.from(e);
    }
  }

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw const EcfOnboardingException('Respuesta inesperada del servidor.');
  }
}

/// Error de las funciones e-CF con el mensaje que arma el servidor, listo
/// para mostrarle al operador.
class EcfOnboardingException implements Exception {
  const EcfOnboardingException(this.message, {this.code, this.detail});

  final String message;
  final String? code;
  final Object? detail;

  factory EcfOnboardingException.from(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] is Map) {
      final err = Map<String, dynamic>.from(details['error'] as Map);
      return EcfOnboardingException(
        (err['message'] as String?) ?? 'Error ${e.status}',
        code: err['code'] as String?,
        detail: err['detail'],
      );
    }
    if (e.status == 404 && details is! Map) {
      return const EcfOnboardingException(
        'La función del servidor no está desplegada (404).',
        code: 'function_not_found',
      );
    }
    return EcfOnboardingException(
      'Error ${e.status}${e.reasonPhrase != null ? ' ${e.reasonPhrase}' : ''}',
    );
  }

  @override
  String toString() => message;
}

final ecfOnboardingRepositoryProvider = Provider<EcfOnboardingRepository>((ref) {
  return EcfOnboardingRepository(ref.watch(supabaseProvider));
});

final ecfRequestsProvider = FutureProvider<List<EcfRequestSummary>>((ref) {
  return ref.watch(ecfOnboardingRepositoryProvider).listRequests();
});

final ecfOnboardingStatusProvider =
    FutureProvider.family<EcfOnboardingStatus, String>((ref, businessId) {
  return ref.watch(ecfOnboardingRepositoryProvider).status(businessId);
});

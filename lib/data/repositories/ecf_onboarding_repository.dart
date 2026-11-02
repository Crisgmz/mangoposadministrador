import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../domain/models/ecf_onboarding.dart';

/// Alta de facturación electrónica de un [EcfOwner]: un negocio de MangoPOS o
/// una empresa de otra app (Busi Pos Web). Todo pasa por dos Edge Functions
/// del repo mangospos:
///   - `ecf-onboarding`: datos, empresa en Alanube, secuencias y modalidad.
///     Valida `is_platform_operator()` y audita en `noc_audit_log`.
///   - `provision-ecf`: preflight y activación (`business_alanube_settings`).
class EcfOnboardingRepository {
  EcfOnboardingRepository(this._client);

  final SupabaseClient _client;

  Future<EcfOnboardingStatus> status(EcfOwner owner) async {
    final data = await _onboarding('status', owner);
    return EcfOnboardingStatus.fromJson(data);
  }

  Future<void> saveData(EcfOwner owner, EcfTaxpayerDraft draft) async {
    await _onboarding('save_data', owner, {'data': draft.toJson()});
  }

  /// Consulta auditada, exclusiva de operadores. La clave no se carga al
  /// listar solicitudes ni al leer su estado, y se conserva sin recortarla.
  Future<EcfOfvCredentials> revealOfvPassword(EcfOwner owner) async {
    final data = await _onboarding('reveal_ofv_password', owner);
    final password = data['ofv_password'];
    if (password is! String || password.isEmpty) {
      throw const EcfOnboardingException(
        'El servidor no devolvió la contraseña de la Oficina Virtual.',
      );
    }
    return EcfOfvCredentials(
      ofvUser: data['ofv_user'] as String?,
      ofvPassword: password,
    );
  }

  /// Copia RNC y razón social del borrador a `fiscal_settings` (lo que usa la
  /// POS y lo que compara el preflight).
  Future<void> syncFiscal(EcfOwner owner) async {
    await _onboarding('sync_fiscal', owner);
  }

  /// Empresas asociadas en Alanube con el RNC del negocio.
  Future<List<EcfCompany>> findCompany(EcfOwner owner) async {
    final data = await _onboarding('find_company', owner);
    return ((data['matches'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => EcfCompany.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<void> linkCompany(EcfOwner owner, String alanubeCompanyId) async {
    await _onboarding('link_company', owner, {
      'alanube_company_id': alanubeCompanyId,
    });
  }

  /// Carga o reemplaza el certificado cifrado para las firmas del negocio.
  /// En una empresa externa el servidor exige [clientAuthorizedStorage]: su
  /// app no le pidió al cliente permiso para guardarlo.
  Future<void> saveCertificate({
    required EcfOwner owner,
    required String certificateFilename,
    required Uint8List certificateBytes,
    required String certificatePassword,
    bool clientAuthorizedStorage = false,
  }) async {
    await _onboarding('save_certificate', owner, {
      'certificate': _certificatePayload(
        certificateFilename,
        certificateBytes,
        certificatePassword,
      ),
      if (clientAuthorizedStorage) 'accept_certificate_storage': true,
    });
  }

  /// Da de alta la empresa en Alanube. Sin archivo explícito, el servidor
  /// usa el certificado guardado con la solicitud.
  Future<EcfCompany?> registerCompany({
    required EcfOwner owner,
    String? certificateFilename,
    Uint8List? certificateBytes,
    String? certificatePassword,
  }) async {
    final certificate = _certificatePayload(
      certificateFilename,
      certificateBytes,
      certificatePassword,
    );
    final data = await _onboarding('register_company', owner, {
      'certificate': ?certificate,
    });
    final company = data['company'];
    return company is Map
        ? EcfCompany.fromJson(Map<String, dynamic>.from(company))
        : null;
  }

  Future<void> saveSequence({
    required EcfOwner owner,
    required String ncfType,
    required int rangeStart,
    required int rangeEnd,
    DateTime? expirationDate,
    String? authorizationNumber,
    int? lastUsed,
  }) async {
    await _onboarding('save_sequence', owner, {
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

  Future<void> setEcfEnabled(EcfOwner owner, bool enabled) async {
    await _onboarding('set_ecf_enabled', owner, {'enabled': enabled});
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

  Future<EcfPostulationInfo> postulationInfo(EcfOwner owner) async {
    final data = await _onboarding('postulation_info', owner);
    return EcfPostulationInfo.fromJson(data);
  }

  /// Alanube firma el XML con el certificado de la empresa y devuelve el
  /// enlace del XML firmado, que es lo que se sube a la OFV.
  Future<String> signDocument({
    required EcfOwner owner,
    required EcfSignKind kind,
    required String filename,
    required Uint8List bytes,
  }) async {
    final data = await _onboarding('sign_document', owner, {
      'kind': kind.code,
      'xml': {'filename': filename, 'content_base64': base64Encode(bytes)},
    });
    final url = data['signed_document_url'];
    if (url is! String || url.isEmpty) {
      throw const EcfOnboardingException('El servidor no devolvió el XML firmado.');
    }
    return url;
  }

  /// Carga un Excel de la DGII (.xlsx, o una hoja en .csv): el de pruebas de
  /// datos e-CF ([setKind] `ecf`) o el de aprobaciones comerciales (`acecf`).
  /// Reemplaza el que hubiera de ese tipo; si el archivo es del otro, falla con
  /// `wrong_test_set`.
  Future<EcfTestSet> importTestSet({
    required EcfOwner owner,
    required String setKind,
    required String filename,
    required Uint8List bytes,
  }) async {
    final data = await _onboarding('import_test_set', owner, {
      'set_kind': setKind,
      'file': {'filename': filename, 'content_base64': base64Encode(bytes)},
    });
    return EcfTestSet.fromJson(_asMap(data['test_set']));
  }

  /// Un lote del envío a la DGII. Sin archivo explícito se firma con el
  /// certificado de la solicitud; si responde `more`, hay que volver a llamar.
  Future<EcfTestSetSendResult> sendTestSet({
    required EcfOwner owner,
    required String setKind,
    String? certificateFilename,
    Uint8List? certificateBytes,
    String? certificatePassword,
  }) async {
    final certificate = _certificatePayload(
      certificateFilename,
      certificateBytes,
      certificatePassword,
    );
    final data = await _onboarding('send_test_set', owner, {
      'set_kind': setKind,
      'certificate': ?certificate,
    });
    return EcfTestSetSendResult.fromJson(data);
  }

  /// Paso 4 del portal: arma los e-CF de la simulación con el set de datos
  /// aceptado como modelo, en las cantidades que pide el portal
  /// ({'31': 1, '32': 1, '32rfce': 1, …}). Volver a generar usa e-NCF nuevos.
  /// El modelo lo resuelve el servidor (set de este negocio, de otra sucursal
  /// con el mismo RNC, o el genérico de la DGII).
  Future<EcfTestSet> generateSimulationSet(
    EcfOwner owner, {
    required Map<String, int> counts,
  }) async {
    final data = await _onboarding('generate_simulation_set', owner, {'counts': counts});
    return EcfTestSet.fromJson(_asMap(data['test_set']));
  }

  /// Consulta los envíos en proceso de un set (`ecf` o `sim`). Sin
  /// [certificate*] usa la sesión con la DGII del último envío; si venció,
  /// la renueva con el certificado guardado, cuando existe.
  Future<EcfTestSet> checkTestSet(
    EcfOwner owner, {
    String setKind = 'ecf',
    String? certificateFilename,
    Uint8List? certificateBytes,
    String? certificatePassword,
  }) async {
    final certificate = _certificatePayload(
      certificateFilename,
      certificateBytes,
      certificatePassword,
    );
    final data = await _onboarding('check_test_set', owner, {
      'set_kind': setKind,
      'certificate': ?certificate,
    });
    return EcfTestSet.fromJson(_asMap(data['test_set']));
  }

  /// XML firmado de un caso, como se mandó a la DGII, y los datos de su
  /// representación impresa (null en las aprobaciones comerciales).
  Future<({String filename, String xml, EcfPrintModel? print})> testCaseXml(
    EcfOwner owner,
    String caseId,
  ) async {
    final data = await _onboarding('test_case_xml', owner, {'case_id': caseId});
    final xml = data['xml'];
    if (xml is! String || xml.isEmpty) {
      throw const EcfOnboardingException('El servidor no devolvió el XML.');
    }
    final print = data['print'];
    return (
      filename: (data['filename'] as String?) ?? '$caseId.xml',
      xml: xml,
      print: print is Map ? EcfPrintModel.fromJson(Map<String, dynamic>.from(print)) : null,
    );
  }

  Future<void> setDgiiAuthorized(EcfOwner owner, bool authorized) async {
    await _onboarding('set_dgii_authorized', owner, {'authorized': authorized});
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
    EcfOwner owner, [
    Map<String, dynamic> params = const {},
  ]) async {
    try {
      final res = await _client.functions.invoke('ecf-onboarding', body: {
        'action': action,
        ...owner.toJson(),
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

  static Map<String, dynamic>? _certificatePayload(
    String? filename,
    Uint8List? bytes,
    String? password,
  ) {
    if (filename == null && bytes == null && password == null) return null;
    if (filename == null || filename.isEmpty || bytes == null ||
        bytes.isEmpty || password == null || password.isEmpty) {
      throw const EcfOnboardingException(
        'Elige el certificado e indica su contraseña.',
      );
    }
    return {
      'filename': filename,
      'content_base64': base64Encode(bytes),
      'password': password,
    };
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
    FutureProvider.family<EcfOnboardingStatus, EcfOwner>((ref, owner) {
  return ref.watch(ecfOnboardingRepositoryProvider).status(owner);
});

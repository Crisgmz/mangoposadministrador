/// Alta de facturación electrónica (e-CF) de un negocio, hecha por un
/// operador de MangoPOS.
///
/// Espejo de la respuesta de la Edge Function `ecf-onboarding` (acción
/// `status`) y del preflight de `provision-ecf`, ambas en el repo mangospos.
/// Las reglas (validaciones, RNC contra Alanube, secuencias) viven en el
/// servidor: acá solo se presenta y se deriva en qué paso va.
class EcfOnboardingStatus {
  const EcfOnboardingStatus({
    required this.businessId,
    required this.businessName,
    required this.environment,
    required this.sequences,
    this.businessAddress,
    this.draft,
    this.fiscal,
    this.rncInSync,
    this.legalNameInSync,
    this.settings,
    this.company,
    this.companyError,
    this.setTest,
    this.setTestError,
  });

  final String businessId;
  final String businessName;

  /// Dirección del local (`businesses.address`), la que sale en el ticket.
  final String? businessAddress;

  /// `production | sandbox` — sale de ALANUBE_BASE_URL, global al servidor.
  final String environment;

  /// Datos capturados en el panel (`ecf_onboarding`). Null si nunca se guardó.
  final EcfTaxpayerDraft? draft;

  /// Lo que la POS tiene en `fiscal_settings`. Null si no hay fila.
  final EcfFiscalSettings? fiscal;

  /// Null cuando no hay borrador contra el cual comparar.
  final bool? rncInSync;
  final bool? legalNameInSync;

  final List<EcfSequence> sequences;

  /// `business_alanube_settings`: existe solo después de activar.
  final EcfAlanubeSettings? settings;

  final EcfCompany? company;

  /// Por qué no se pudo leer la empresa en Alanube, si falló.
  final String? companyError;

  /// Set de pruebas vigente. Solo viene mientras la certificación está en curso.
  final EcfSetTest? setTest;
  final String? setTestError;

  bool get isProduction => environment == 'production';

  /// ULID de la empresa: del borrador o, en negocios activados antes del
  /// panel (Tropella), de la configuración de Alanube.
  String? get companyId =>
      draft?.alanubeCompanyId ?? settings?.alanubeCompanyId;

  bool get fiscalInSync => rncInSync == true && legalNameInSync == true;

  bool get hasData => draft?.isCompleteForRegistration ?? false;
  bool get hasCompany => companyId != null;
  bool get hasSequences => sequences.any((s) => s.isUsable);
  bool get isProvisioned => settings != null && settings!.mode != 'physical';
  bool get ecfEnabled => fiscal?.ecfEnabled ?? false;

  /// Autorizado por la DGII como emisor electrónico. Además de la marca del
  /// operador, cuenta tener secuencias e-NCF o estar activado: la DGII no
  /// entrega secuencias E a quien no autorizó.
  bool get isCertified =>
      draft?.dgiiAuthorizedAt != null || hasSequences || isProvisioned;

  /// Paso en curso (1–5); 6 cuando ya emite.
  int get currentStep {
    if (ecfEnabled && isProvisioned) return 6;
    if (!hasCompany && !hasData) return 1;
    if (!hasCompany) return 2;
    if (!isCertified) return 3;
    if (!hasSequences) return 4;
    return 5;
  }

  factory EcfOnboardingStatus.fromJson(Map<String, dynamic> json) {
    final business = _map(json['business']) ?? const {};
    final sync = _map(json['fiscal_sync']);
    final draft = _map(json['onboarding']);
    final fiscal = _map(json['fiscal']);
    final settings = _map(json['alanube_settings']);
    final company = _map(json['company']);
    final setTest = _map(json['set_test']);
    return EcfOnboardingStatus(
      businessId: (business['id'] as String?) ?? '',
      businessName: (business['business_name'] as String?) ?? '',
      businessAddress: business['address'] as String?,
      environment: (json['environment'] as String?) ?? 'production',
      draft: draft == null ? null : EcfTaxpayerDraft.fromJson(draft),
      fiscal: fiscal == null ? null : EcfFiscalSettings.fromJson(fiscal),
      rncInSync: sync?['rnc_matches'] as bool?,
      legalNameInSync: sync?['legal_name_matches'] as bool?,
      sequences: ((json['sequences'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfSequence.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      settings: settings == null ? null : EcfAlanubeSettings.fromJson(settings),
      company: company == null ? null : EcfCompany.fromJson(company),
      companyError: json['company_error'] as String?,
      setTest: setTest == null ? null : EcfSetTest.fromJson(setTest),
      setTestError: json['set_test_error'] as String?,
    );
  }
}

class EcfTaxpayerDraft {
  const EcfTaxpayerDraft({
    this.rnc,
    this.legalName,
    this.tradeName,
    this.fiscalAddress,
    this.province,
    this.municipality,
    this.email,
    this.alanubeCompanyId,
    this.companyLinkedVia,
    this.companyLinkedAt,
    this.setTestId,
    this.setTestCreatedAt,
    this.postulationSignedAt,
    this.declarationSignedAt,
    this.rolesSignedAt,
    this.dgiiAuthorizedAt,
    this.requestedAt,
    this.contactName,
    this.contactPhone,
    this.alreadyAuthorized,
  });

  final String? rnc;
  final String? legalName;
  final String? tradeName;
  final String? fiscalAddress;
  final String? province;
  final String? municipality;
  final String? email;
  final String? alanubeCompanyId;

  /// `registered` (creada desde el panel) | `existing` (ya existía).
  final String? companyLinkedVia;
  final DateTime? companyLinkedAt;

  // Certificación: cuándo se hizo cada paso DESDE EL PANEL. Firmar no es
  // subir a la OFV; la verdad la tiene la DGII.
  final String? setTestId;
  final DateTime? setTestCreatedAt;
  final DateTime? postulationSignedAt;
  final DateTime? declarationSignedAt;
  final DateTime? rolesSignedAt;

  /// Marcado a mano por el operador cuando la DGII lo autoriza.
  final DateTime? dgiiAuthorizedAt;

  /// Solicitud hecha por el cliente desde la POS. Null si la empezó un operador.
  final DateTime? requestedAt;
  final String? contactName;
  final String? contactPhone;

  /// Lo que declaró el cliente: ya es emisor electrónico autorizado.
  final bool? alreadyAuthorized;

  /// Lo mínimo que exige `POST /company` de Alanube.
  bool get isCompleteForRegistration =>
      _filled(rnc) && _filled(legalName) && _filled(fiscalAddress);

  factory EcfTaxpayerDraft.fromJson(Map<String, dynamic> json) {
    return EcfTaxpayerDraft(
      rnc: json['rnc'] as String?,
      legalName: json['legal_name'] as String?,
      tradeName: json['trade_name'] as String?,
      fiscalAddress: json['fiscal_address'] as String?,
      province: json['province'] as String?,
      municipality: json['municipality'] as String?,
      email: json['email'] as String?,
      alanubeCompanyId: json['alanube_company_id'] as String?,
      companyLinkedVia: json['company_linked_via'] as String?,
      companyLinkedAt: _date(json['company_linked_at']),
      setTestId: json['set_test_id'] as String?,
      setTestCreatedAt: _date(json['set_test_created_at']),
      postulationSignedAt: _date(json['postulation_signed_at']),
      declarationSignedAt: _date(json['declaration_signed_at']),
      rolesSignedAt: _date(json['roles_signed_at']),
      dgiiAuthorizedAt: _date(json['dgii_authorized_at']),
      requestedAt: _date(json['requested_at']),
      contactName: json['contact_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
      alreadyAuthorized: json['already_authorized'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'rnc': rnc,
        'legal_name': legalName,
        'trade_name': tradeName,
        'fiscal_address': fiscalAddress,
        'province': province,
        'municipality': municipality,
        'email': email,
      };
}

class EcfFiscalSettings {
  const EcfFiscalSettings({
    required this.ecfEnabled,
    this.rnc,
    this.legalName,
    this.defaultNcfType,
  });

  final String? rnc;
  final String? legalName;
  final bool ecfEnabled;
  final String? defaultNcfType;

  factory EcfFiscalSettings.fromJson(Map<String, dynamic> json) {
    return EcfFiscalSettings(
      rnc: json['rnc'] as String?,
      legalName: json['business_legal_name'] as String?,
      ecfEnabled: (json['ecf_enabled'] as bool?) ?? false,
      defaultNcfType: json['default_ncf_type'] as String?,
    );
  }
}

class EcfSequence {
  const EcfSequence({
    required this.id,
    required this.ncfType,
    required this.rangeStart,
    required this.rangeEnd,
    required this.currentNumber,
    required this.isActive,
    this.expirationDate,
    this.authorization,
  });

  final String id;
  final String ncfType;
  final int rangeStart;
  final int rangeEnd;
  final int currentNumber;
  final bool isActive;
  final DateTime? expirationDate;
  final String? authorization;

  /// Tipos donde `emit-document` manda la fecha de vencimiento y la DGII la
  /// valida (código 145 si falta).
  static const typesRequiringExpiration = {'E31', 'E44', 'E45'};

  /// Números que quedan. La BD asigna `max(current_number + 1, range_start)`,
  /// así que un `current_number` por debajo del rango cuenta como no usado.
  int get available {
    final used = currentNumber < rangeStart - 1 ? rangeStart - 1 : currentNumber;
    final left = rangeEnd - used;
    return left < 0 ? 0 : left;
  }

  bool get missingExpiration =>
      typesRequiringExpiration.contains(ncfType) && expirationDate == null;

  bool get isExpired {
    final exp = expirationDate;
    if (exp == null) return false;
    final today = DateTime.now();
    return exp.isBefore(DateTime(today.year, today.month, today.day));
  }

  /// Sirve para emitir: activa, con números y sin trabas de vencimiento.
  bool get isUsable =>
      isActive && available > 0 && !missingExpiration && !isExpired;

  factory EcfSequence.fromJson(Map<String, dynamic> json) {
    return EcfSequence(
      id: json['id'] as String,
      ncfType: json['ncf_type'] as String,
      rangeStart: (json['range_start'] as num?)?.toInt() ?? 1,
      rangeEnd: (json['range_end'] as num?)?.toInt() ?? 0,
      currentNumber: (json['current_number'] as num?)?.toInt() ?? 0,
      isActive: (json['is_active'] as bool?) ?? false,
      expirationDate: _date(json['expiration_date']),
      authorization: json['authorized_by'] as String?,
    );
  }
}

class EcfAlanubeSettings {
  const EcfAlanubeSettings({
    required this.alanubeCompanyId,
    required this.environment,
    required this.mode,
    required this.certificationStatus,
    required this.webhooksConfigured,
  });

  final String alanubeCompanyId;
  final String environment;

  /// `physical | electronic | hybrid`.
  final String mode;
  final String certificationStatus;
  final bool webhooksConfigured;

  factory EcfAlanubeSettings.fromJson(Map<String, dynamic> json) {
    return EcfAlanubeSettings(
      alanubeCompanyId: json['alanube_company_id'] as String,
      environment: (json['environment'] as String?) ?? 'production',
      mode: (json['mode'] as String?) ?? 'hybrid',
      certificationStatus:
          (json['certification_status'] as String?) ?? 'pending',
      webhooksConfigured: (json['webhooks_configured'] as bool?) ?? false,
    );
  }
}

/// Empresa en Alanube (resumen que arma el servidor, sin datos sensibles).
class EcfCompany {
  const EcfCompany({
    required this.id,
    this.name,
    this.tradeName,
    this.identification,
    this.address,
    this.certificationStep,
    this.certificateName,
    this.certificateIssuer,
    this.certificateEndDate,
    this.webhooksOk,
    this.assignedToBusinessId,
    this.receptionUrl,
    this.approvalUrl,
    this.authenticationUrl,
  });

  final String id;
  final String? name;
  final String? tradeName;
  final String? identification;
  final String? address;

  /// Contador de Alanube. OJO: no es confiable — Tropella marcaba 2 estando
  /// autorizada por la DGII.
  final int? certificationStep;
  final String? certificateName;
  final String? certificateIssuer;

  /// Alanube la manda como "2027-04-23 21:30:54".
  final DateTime? certificateEndDate;

  /// Null cuando la respuesta no lo trae (búsqueda por RNC).
  final bool? webhooksOk;

  /// En la búsqueda: negocio de MangoPOS que ya usa esta empresa.
  final String? assignedToBusinessId;

  /// URLs que se registran en la postulación de la DGII.
  final String? receptionUrl;
  final String? approvalUrl;
  final String? authenticationUrl;

  bool get hasCertificate => certificateName != null;

  bool get certificateExpired =>
      certificateEndDate != null &&
      certificateEndDate!.isBefore(DateTime.now());

  factory EcfCompany.fromJson(Map<String, dynamic> json) {
    final cert = _map(json['certificate']);
    final urls = _map(json['company_urls']);
    return EcfCompany(
      id: json['id'] as String,
      name: json['name'] as String?,
      tradeName: json['trade_name'] as String?,
      identification: json['identification']?.toString(),
      address: json['address'] as String?,
      certificationStep: (json['certification_step'] as num?)?.toInt(),
      certificateName: cert?['name'] as String?,
      certificateIssuer: cert?['issuer'] as String?,
      certificateEndDate: _date(cert?['end_date']),
      webhooksOk: json['webhooks_ok'] as bool?,
      assignedToBusinessId: json['assigned_to_business_id'] as String?,
      receptionUrl: urls?['reception'] as String?,
      approvalUrl: urls?['approval'] as String?,
      authenticationUrl: urls?['authentication'] as String?,
    );
  }
}

/// Un chequeo del preflight de `provision-ecf`.
class EcfCheck {
  const EcfCheck({
    required this.key,
    required this.level,
    required this.message,
  });

  final String key;

  /// `ok | warn | fail`.
  final String level;
  final String message;

  bool get isFail => level == 'fail';
  bool get isWarn => level == 'warn';

  factory EcfCheck.fromJson(Map<String, dynamic> json) {
    return EcfCheck(
      key: (json['key'] as String?) ?? '',
      level: (json['level'] as String?) ?? 'warn',
      message: (json['message'] as String?) ?? '',
    );
  }
}

/// Resultado de `provision-ecf`, con o sin escritura.
class EcfPreflightResult {
  const EcfPreflightResult({
    required this.checks,
    required this.wrote,
    this.nextStep,
  });

  final List<EcfCheck> checks;
  final bool wrote;
  final String? nextStep;

  bool get hasFailures => checks.any((c) => c.isFail);
  int get warnings => checks.where((c) => c.isWarn).length;

  factory EcfPreflightResult.fromJson(Map<String, dynamic> json) {
    return EcfPreflightResult(
      checks: ((json['checks'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfCheck.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      wrote: (json['wrote'] as bool?) ?? false,
      nextStep: json['next_step'] as String?,
    );
  }
}

/// Solicitud de facturación electrónica hecha por un cliente desde la POS.
class EcfRequestSummary {
  const EcfRequestSummary({
    required this.businessId,
    required this.stage,
    this.businessName,
    this.rnc,
    this.legalName,
    this.requestedAt,
    this.contactName,
    this.contactPhone,
    this.alreadyAuthorized,
  });

  final String businessId;

  /// `company | certification | sequences | activation | active` (lo calcula
  /// el servidor, igual que en la POS).
  final String stage;
  final String? businessName;
  final String? rnc;
  final String? legalName;
  final DateTime? requestedAt;
  final String? contactName;
  final String? contactPhone;
  final bool? alreadyAuthorized;

  bool get isActive => stage == 'active';

  String get stageLabel {
    switch (stage) {
      case 'company':
        return 'Falta registrar la empresa';
      case 'certification':
        return 'Certificación DGII';
      case 'sequences':
        return 'Faltan secuencias';
      case 'activation':
        return 'Listo para activar';
      case 'active':
        return 'Activa';
      default:
        return stage;
    }
  }

  factory EcfRequestSummary.fromJson(Map<String, dynamic> json) {
    return EcfRequestSummary(
      businessId: json['business_id'] as String,
      stage: (json['stage'] as String?) ?? 'company',
      businessName: json['business_name'] as String?,
      rnc: json['rnc'] as String?,
      legalName: json['legal_name'] as String?,
      requestedAt: _date(json['requested_at']),
      contactName: json['contact_name'] as String?,
      contactPhone: json['contact_phone'] as String?,
      alreadyAuthorized: json['already_authorized'] as bool?,
    );
  }
}

/// Tipos de XML de habilitación que firma Alanube.
enum EcfSignKind {
  postulation('postulation', 'XML de postulación'),
  declaration('declaration', 'Declaración jurada'),
  roles('roles', 'XML de asignación de roles');

  const EcfSignKind(this.code, this.label);
  final String code;
  final String label;
}

/// Set de pruebas de certificación (20 comprobantes que Alanube manda a la DGII).
class EcfSetTest {
  const EcfSetTest({
    required this.status,
    required this.documents,
    this.id,
    this.retryNumber,
    this.processed,
    this.documentsZipUrl,
    this.resumesZipUrl,
  });

  final String? id;

  /// `REGISTERED | IN_PROGRESS | ACCEPTED | REJECTED` (u otro que invente Alanube).
  final String status;
  final int? retryNumber;
  final int? processed;
  final List<EcfSetTestDocument> documents;

  /// Zips con los XML y PDF que se suben a la OFV. Solo al aceptarse.
  final String? documentsZipUrl;
  final String? resumesZipUrl;

  static const total = 20;

  bool get isAccepted => status == 'ACCEPTED';
  bool get isRejected => status == 'REJECTED';
  bool get isFinal => isAccepted || isRejected;

  List<EcfSetTestDocument> get rejectedDocuments =>
      documents.where((d) => d.status == 'REJECTED').toList(growable: false);

  String get statusLabel {
    switch (status) {
      case 'ACCEPTED':
        return 'Aceptado';
      case 'REJECTED':
        return 'Rechazado';
      case 'REGISTERED':
        return 'Registrado';
      case 'IN_PROGRESS':
        return 'En curso';
      default:
        return status;
    }
  }

  factory EcfSetTest.fromJson(Map<String, dynamic> json) {
    return EcfSetTest(
      id: json['id'] as String?,
      status: (json['status'] as String?) ?? 'DESCONOCIDO',
      retryNumber: (json['retry_number'] as num?)?.toInt(),
      processed: (json['processed'] as num?)?.toInt(),
      documents: ((json['documents'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfSetTestDocument.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      documentsZipUrl: json['documents_zip_url'] as String?,
      resumesZipUrl: json['resumes_zip_url'] as String?,
    );
  }
}

class EcfSetTestDocument {
  const EcfSetTestDocument({required this.type, required this.status, this.encf});

  final String type;
  final String status;
  final String? encf;

  factory EcfSetTestDocument.fromJson(Map<String, dynamic> json) {
    return EcfSetTestDocument(
      type: (json['type'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      encf: json['encf'] as String?,
    );
  }
}

/// Producto representativo con que Alanube arma los comprobantes del set.
class EcfItemExample {
  const EcfItemExample({
    required this.itemName,
    required this.billingIndicator,
    required this.goodServiceIndicator,
    required this.unitPrice,
    this.description,
  });

  final String itemName;

  /// 1 = ITBIS 18%, 2 = 16%, 3 = 0%, 4 = exento.
  final int billingIndicator;

  /// 1 = bien, 2 = servicio.
  final int goodServiceIndicator;

  /// Entero: Alanube no acepta decimales aquí.
  final int unitPrice;
  final String? description;

  factory EcfItemExample.fromJson(Map<String, dynamic> json) {
    return EcfItemExample(
      itemName: (json['item_name'] as String?) ?? '',
      billingIndicator: (json['billing_indicator'] as num?)?.toInt() ?? 1,
      goodServiceIndicator: (json['good_service_indicator'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toInt() ?? 1,
      description: json['item_description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'item_name': itemName,
        'billing_indicator': billingIndicator,
        'good_service_indicator': goodServiceIndicator,
        'unit_price': unitPrice,
        if (description != null && description!.trim().isNotEmpty)
          'item_description': description,
      };
}

/// Lo que se copia en el formulario de postulación de la OFV.
class EcfPostulationInfo {
  const EcfPostulationInfo({
    this.softwareType,
    this.softwareName,
    this.softwareVersion,
    this.providerRnc,
    this.providerName,
    this.providerTradeName,
    this.receptionUrl,
    this.approvalUrl,
    this.authenticationUrl,
    this.companyError,
    this.itemSuggestion,
  });

  final String? softwareType;
  final String? softwareName;
  final String? softwareVersion;
  final String? providerRnc;
  final String? providerName;
  final String? providerTradeName;
  final String? receptionUrl;
  final String? approvalUrl;
  final String? authenticationUrl;
  final String? companyError;
  final EcfItemExample? itemSuggestion;

  factory EcfPostulationInfo.fromJson(Map<String, dynamic> json) {
    final provider = _map(json['provider']) ?? const {};
    final urls = _map(json['company_urls']);
    final suggestion = _map(json['item_suggestion']);
    return EcfPostulationInfo(
      softwareType: provider['software_type'] as String?,
      softwareName: provider['software_name'] as String?,
      softwareVersion: provider['software_version'] as String?,
      providerRnc: provider['provider_rnc'] as String?,
      providerName: provider['provider_name'] as String?,
      providerTradeName: provider['provider_trade_name'] as String?,
      receptionUrl: urls?['reception'] as String?,
      approvalUrl: urls?['approval'] as String?,
      authenticationUrl: urls?['authentication'] as String?,
      companyError: json['company_error'] as String?,
      itemSuggestion:
          suggestion == null ? null : EcfItemExample.fromJson(suggestion),
    );
  }
}

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

bool _filled(String? v) => v != null && v.trim().isNotEmpty;

DateTime? _date(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v.replaceFirst(' ', 'T'));
}

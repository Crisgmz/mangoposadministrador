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
    this.testSet,
    this.approvalSet,
    this.simulationSet,
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

  /// Set de pruebas de la DGII cargado. Solo viene mientras la certificación
  /// está en curso.
  final EcfTestSet? testSet;

  /// Aprobaciones comerciales de la DGII cargadas (paso siguiente del set).
  final EcfTestSet? approvalSet;

  /// e-CF de la simulación (paso 4 del portal), generados desde el set de datos.
  final EcfTestSet? simulationSet;

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
    final testSet = _map(json['test_set']);
    final approvalSet = _map(json['approval_set']);
    final simulationSet = _map(json['simulation_set']);
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
      testSet: testSet == null ? null : EcfTestSet.fromJson(testSet),
      approvalSet: approvalSet == null ? null : EcfTestSet.fromJson(approvalSet),
      simulationSet: simulationSet == null ? null : EcfTestSet.fromJson(simulationSet),
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

/// Set de pruebas de la DGII: el Excel que entrega su portal de certificación,
/// ya cargado. `ecf-onboarding` firma cada caso con el certificado del cliente
/// y lo manda al ambiente CerteCF.
class EcfTestSet {
  const EcfTestSet({
    required this.cases,
    this.kind = 'ecf',
    this.filename,
    this.loadedAt,
    this.sessionExpiresAt,
  });

  /// `ecf` = pruebas de datos e-CF; `acecf` = pruebas de aprobación comercial;
  /// `sim` = pruebas de simulación e-CF.
  final String kind;
  final String? filename;
  final DateTime? loadedAt;

  bool get isApprovals => kind == 'acecf';
  bool get isSimulation => kind == 'sim';

  /// Mientras no venza, consultar a la DGII no pide el certificado.
  final DateTime? sessionExpiresAt;
  final List<EcfTestCase> cases;

  int count(bool Function(EcfTestCase c) test) => cases.where(test).length;

  int get accepted => count((c) => c.isAccepted);
  int get inProcess => count((c) => c.status == 'sent');
  int get toSend => count((c) => c.status == 'pending' || c.status == 'error');
  int get summaries => count((c) => c.isSummary);

  List<EcfTestCase> get rejected =>
      cases.where((c) => c.status == 'rejected').toList(growable: false);
  List<EcfTestCase> get failed =>
      cases.where((c) => c.status == 'error').toList(growable: false);

  bool get isEmpty => cases.isEmpty;

  /// La DGII aceptó todo (con o sin observaciones).
  bool get isComplete => cases.isNotEmpty && cases.every((c) => c.isAccepted);

  /// Un rechazo obliga a reiniciar el set en el portal de la DGII.
  bool get canSend => toSend > 0 && rejected.isEmpty;
  bool get canCheck => inProcess > 0;

  factory EcfTestSet.fromJson(Map<String, dynamic> json) {
    return EcfTestSet(
      kind: (json['kind'] as String?) ?? 'ecf',
      filename: json['filename'] as String?,
      loadedAt: _date(json['loaded_at']),
      sessionExpiresAt: _date(json['session_expires_at']),
      cases: ((json['cases'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfTestCase.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }
}

/// Un comprobante del set (una fila de la hoja ECF).
class EcfTestCase {
  const EcfTestCase({
    required this.id,
    required this.position,
    required this.ecfType,
    required this.encf,
    required this.via,
    required this.status,
    required this.messages,
    this.total,
    this.modifies,
    this.trackId,
    this.securityCode,
    this.sentAt,
  });

  final String id;
  final int position;

  /// `31`, `32`… sin la E.
  final String ecfType;
  final String encf;
  final double? total;

  /// `ecf` → Recepción. `rfce` → E32 menor de 250 mil: va su resumen y el XML
  /// completo se sube a mano en el portal de la DGII.
  final String via;

  /// `pending | sent | accepted | conditional | rejected | error`.
  final String status;
  final String? modifies;
  final String? trackId;
  final String? securityCode;
  final List<EcfDgiiMessage> messages;
  final DateTime? sentAt;

  bool get isSummary => via == 'rfce';

  /// Aprobación comercial (el contribuyente firma como comprador).
  bool get isApproval => via == 'acecf';
  bool get isAccepted => status == 'accepted' || status == 'conditional';

  /// Ya se firmó: hay XML para descargar.
  bool get hasXml =>
      status == 'sent' || isAccepted || status == 'rejected';

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pendiente';
      case 'sent':
        return 'En proceso';
      case 'accepted':
        return 'Aceptado';
      case 'conditional':
        return 'Aceptado condicional';
      case 'rejected':
        return 'Rechazado';
      case 'error':
        return 'No se pudo enviar';
      default:
        return status;
    }
  }

  factory EcfTestCase.fromJson(Map<String, dynamic> json) {
    return EcfTestCase(
      id: json['id'] as String,
      position: (json['position'] as num?)?.toInt() ?? 0,
      ecfType: (json['ecf_type'] as String?) ?? '',
      encf: (json['encf'] as String?) ?? '',
      total: (json['total'] as num?)?.toDouble(),
      via: (json['via'] as String?) ?? 'ecf',
      status: (json['status'] as String?) ?? 'pending',
      modifies: json['modifies'] as String?,
      trackId: json['track_id'] as String?,
      securityCode: json['security_code'] as String?,
      messages: ((json['messages'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfDgiiMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      sentAt: _date(json['sent_at']),
    );
  }
}

class EcfDgiiMessage {
  const EcfDgiiMessage({required this.message, this.code});

  final String? code;
  final String message;

  factory EcfDgiiMessage.fromJson(Map<String, dynamic> json) {
    return EcfDgiiMessage(
      code: json['code']?.toString(),
      message: (json['message'] as String?) ?? '',
    );
  }
}

/// Respuesta de un lote de `send_test_set`.
class EcfTestSetSendResult {
  const EcfTestSetSendResult({
    required this.sent,
    required this.more,
    required this.testSet,
    this.stoppedReason,
  });

  final int sent;

  /// Quedó trabajo: el panel vuelve a llamar con el mismo certificado.
  final bool more;
  final String? stoppedReason;
  final EcfTestSet testSet;

  factory EcfTestSetSendResult.fromJson(Map<String, dynamic> json) {
    return EcfTestSetSendResult(
      sent: (json['sent'] as num?)?.toInt() ?? 0,
      more: (json['more'] as bool?) ?? false,
      stoppedReason: json['stopped_reason'] as String?,
      testSet: EcfTestSet.fromJson(_map(json['test_set']) ?? const {}),
    );
  }
}

/// Datos de la representación impresa (RI) de un e-CF ya firmado, armados
/// por el servidor con lo mismo que se firmó (Informe Técnico e-CF de la DGII,
/// sección 18). Los montos vienen como en el XML.
class EcfPrintModel {
  const EcfPrintModel({
    required this.typeCode,
    required this.typeName,
    required this.encf,
    required this.issuer,
    required this.items,
    required this.adjustments,
    required this.totals,
    required this.signedAt,
    required this.securityCode,
    required this.qrUrl,
    required this.consumerSummary,
    this.dueDate,
    this.modifiedEncf,
    this.modifiedDate,
    this.modification,
    this.modificationReason,
    this.buyer,
    this.currency,
  });

  final String typeCode;

  /// En palabras: "Factura de Crédito Fiscal Electrónica"…
  final String typeName;
  final String encf;
  final String? dueDate;
  final String? modifiedEncf;
  final String? modifiedDate;

  /// Código de modificación en palabras.
  final String? modification;
  final String? modificationReason;
  final EcfPrintIssuer issuer;
  final EcfPrintBuyer? buyer;
  final List<EcfPrintItem> items;
  final List<EcfPrintAdjustment> adjustments;
  final EcfPrintTotals totals;
  final EcfPrintCurrency? currency;

  /// Fecha de firma digital, dd-MM-yyyy HH:mm:ss.
  final String signedAt;
  final String securityCode;
  final String qrUrl;

  /// Factura de consumo menor de 250 mil (QR de consulta de consumo).
  final bool consumerSummary;

  factory EcfPrintModel.fromJson(Map<String, dynamic> json) {
    final buyer = _map(json['buyer']);
    final currency = _map(json['currency']);
    return EcfPrintModel(
      typeCode: (json['type_code'] as String?) ?? '',
      typeName: (json['type_name'] as String?) ?? '',
      encf: (json['encf'] as String?) ?? '',
      dueDate: json['due_date'] as String?,
      modifiedEncf: json['modified_encf'] as String?,
      modifiedDate: json['modified_date'] as String?,
      modification: json['modification'] as String?,
      modificationReason: json['modification_reason'] as String?,
      issuer: EcfPrintIssuer.fromJson(_map(json['issuer']) ?? const {}),
      buyer: buyer == null ? null : EcfPrintBuyer.fromJson(buyer),
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfPrintItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      adjustments: ((json['adjustments'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EcfPrintAdjustment.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      totals: EcfPrintTotals.fromJson(_map(json['totals']) ?? const {}),
      currency: currency == null ? null : EcfPrintCurrency.fromJson(currency),
      signedAt: (json['signed_at'] as String?) ?? '',
      securityCode: (json['security_code'] as String?) ?? '',
      qrUrl: (json['qr_url'] as String?) ?? '',
      consumerSummary: (json['consumer_summary'] as bool?) ?? false,
    );
  }
}

class EcfPrintIssuer {
  const EcfPrintIssuer({
    required this.rnc,
    this.tradeName,
    this.legalName,
    this.branch,
    this.address,
    this.municipality,
    this.province,
    this.phone,
    this.email,
    this.issueDate,
  });

  final String rnc;
  final String? tradeName;
  final String? legalName;
  final String? branch;
  final String? address;

  /// En palabras (el XML lleva el código de la DGII).
  final String? municipality;
  final String? province;
  final String? phone;
  final String? email;
  final String? issueDate;

  factory EcfPrintIssuer.fromJson(Map<String, dynamic> json) {
    return EcfPrintIssuer(
      rnc: (json['rnc'] as String?) ?? '',
      tradeName: json['trade_name'] as String?,
      legalName: json['legal_name'] as String?,
      branch: json['branch'] as String?,
      address: json['address'] as String?,
      municipality: json['municipality'] as String?,
      province: json['province'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      issueDate: json['issue_date'] as String?,
    );
  }
}

class EcfPrintBuyer {
  const EcfPrintBuyer({this.name, this.rnc, this.foreignId});

  final String? name;
  final String? rnc;
  final String? foreignId;

  factory EcfPrintBuyer.fromJson(Map<String, dynamic> json) {
    return EcfPrintBuyer(
      name: json['name'] as String?,
      rnc: json['rnc'] as String?,
      foreignId: json['foreign_id'] as String?,
    );
  }
}

class EcfPrintItem {
  const EcfPrintItem({
    required this.line,
    required this.exempt,
    required this.description,
    this.quantity,
    this.detail,
    this.unit,
    this.price,
    this.itbis,
    this.discount,
    this.surcharge,
    this.value,
  });

  final String line;

  /// La RI pone "E" delante de la descripción de lo exento.
  final bool exempt;
  final String description;
  final String? quantity;
  final String? detail;
  final String? unit;
  final String? price;
  final String? itbis;
  final String? discount;
  final String? surcharge;
  final String? value;

  factory EcfPrintItem.fromJson(Map<String, dynamic> json) {
    return EcfPrintItem(
      line: (json['line'] as String?) ?? '',
      exempt: (json['exempt'] as bool?) ?? false,
      description: (json['description'] as String?) ?? '',
      quantity: json['quantity'] as String?,
      detail: json['detail'] as String?,
      unit: json['unit'] as String?,
      price: json['price'] as String?,
      itbis: json['itbis'] as String?,
      discount: json['discount'] as String?,
      surcharge: json['surcharge'] as String?,
      value: json['value'] as String?,
    );
  }
}

class EcfPrintAdjustment {
  const EcfPrintAdjustment({required this.description, required this.kind, this.percent, this.amount});

  final String description;

  /// `D` descuento, `R` recargo.
  final String kind;
  final String? percent;
  final String? amount;

  factory EcfPrintAdjustment.fromJson(Map<String, dynamic> json) {
    return EcfPrintAdjustment(
      description: (json['description'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? '',
      percent: json['percent'] as String?,
      amount: json['amount'] as String?,
    );
  }
}

class EcfPrintTotals {
  const EcfPrintTotals({
    this.taxed,
    this.exempt,
    this.itbis,
    this.additionalTaxes,
    this.itbisWithheld,
    this.isrWithheld,
    this.total,
  });

  final String? taxed;
  final String? exempt;
  final String? itbis;
  final String? additionalTaxes;
  final String? itbisWithheld;
  final String? isrWithheld;
  final String? total;

  factory EcfPrintTotals.fromJson(Map<String, dynamic> json) {
    return EcfPrintTotals(
      taxed: json['taxed'] as String?,
      exempt: json['exempt'] as String?,
      itbis: json['itbis'] as String?,
      additionalTaxes: json['additional_taxes'] as String?,
      itbisWithheld: json['itbis_withheld'] as String?,
      isrWithheld: json['isr_withheld'] as String?,
      total: json['total'] as String?,
    );
  }
}

class EcfPrintCurrency {
  const EcfPrintCurrency({required this.code, this.rate, this.total});

  final String code;
  final String? rate;
  final String? total;

  factory EcfPrintCurrency.fromJson(Map<String, dynamic> json) {
    return EcfPrintCurrency(
      code: (json['code'] as String?) ?? '',
      rate: json['rate'] as String?,
      total: json['total'] as String?,
    );
  }
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

  factory EcfPostulationInfo.fromJson(Map<String, dynamic> json) {
    final provider = _map(json['provider']) ?? const {};
    final urls = _map(json['company_urls']);
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

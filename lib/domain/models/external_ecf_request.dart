/// Solicitud de facturación electrónica que llegó de OTRA app que comparte
/// esta cuenta de Alanube (hoy Busi Pos Web / flutter_shop+).
///
/// No es un negocio de MangoPOS: vive en la base de la app que la pidió, y
/// acá solo llega la bandeja de entrada para atenderla en un solo lugar. Por
/// eso la fila NO lleva al detalle de un negocio —no existe— sino a un cuadro
/// con los datos y el seguimiento.
class ExternalEcfRequest {
  const ExternalEcfRequest({
    required this.id,
    required this.source,
    required this.externalId,
    required this.status,
    required this.companyRegistered,
    this.companyName,
    this.rnc,
    this.legalName,
    this.tradeName,
    this.email,
    this.contactName,
    this.contactPhone,
    this.alreadyAuthorized,
    this.alanubeCompanyId,
    this.requestedAt,
    this.receivedAt,
    this.notes,
    this.handledAt,
  });

  final String id;

  /// Qué app la mandó ('flutter_shop+').
  final String source;

  /// Id de la empresa en la app de origen.
  final String externalId;

  /// `new | in_progress | done | discarded`.
  final String status;

  /// false = la empresa NO quedó registrada en Alanube (RNC ya existente o
  /// certificado rechazado). Son las que hay que mirar primero.
  final bool companyRegistered;

  final String? companyName;
  final String? rnc;
  final String? legalName;
  final String? tradeName;
  final String? email;
  final String? contactName;
  final String? contactPhone;
  final bool? alreadyAuthorized;
  final String? alanubeCompanyId;
  final DateTime? requestedAt;
  final DateTime? receivedAt;
  final String? notes;
  final DateTime? handledAt;

  bool get isOpen => status == 'new' || status == 'in_progress';

  /// Nombre con el que se muestra la fila.
  String get displayName =>
      companyName ?? legalName ?? tradeName ?? 'Empresa $externalId';

  String get statusLabel {
    switch (status) {
      case 'new':
        return 'Nueva';
      case 'in_progress':
        return 'En proceso';
      case 'done':
        return 'Atendida';
      case 'discarded':
        return 'Descartada';
      default:
        return status;
    }
  }

  /// Lo primero que tiene que ver quien la atiende: si el alta con el
  /// proveedor quedó pendiente, eso manda sobre el estado de seguimiento.
  String get headline => companyRegistered
      ? 'Registrada con el proveedor'
      : 'Sin registrar — revisar RNC o certificado';

  factory ExternalEcfRequest.fromJson(Map<String, dynamic> json) {
    DateTime? date(Object? v) => DateTime.tryParse(v?.toString() ?? '');
    String? text(Object? v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    return ExternalEcfRequest(
      id: (json['id'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      externalId: (json['external_id'] ?? '').toString(),
      status: (json['status'] ?? 'new').toString(),
      companyRegistered: json['company_registered'] == true,
      companyName: text(json['company_name']),
      rnc: text(json['rnc']),
      legalName: text(json['legal_name']),
      tradeName: text(json['trade_name']),
      email: text(json['email']),
      contactName: text(json['contact_name']),
      contactPhone: text(json['contact_phone']),
      alreadyAuthorized: json['already_authorized'] as bool?,
      alanubeCompanyId: text(json['alanube_company_id']),
      requestedAt: date(json['requested_at']),
      receivedAt: date(json['received_at']),
      notes: text(json['notes']),
      handledAt: date(json['handled_at']),
    );
  }
}

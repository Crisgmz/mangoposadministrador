import '_json_helpers.dart';
import 'business_environment.dart';

enum IncidentSeverity { info, warning, critical, unknown }

extension IncidentSeverityX on IncidentSeverity {
  static IncidentSeverity fromText(String? raw) {
    switch (raw) {
      case 'critical':
        return IncidentSeverity.critical;
      case 'warning':
        return IncidentSeverity.warning;
      case 'info':
        return IncidentSeverity.info;
      default:
        return IncidentSeverity.unknown;
    }
  }

  String get label {
    switch (this) {
      case IncidentSeverity.critical:
        return 'Crítico';
      case IncidentSeverity.warning:
        return 'Atención';
      case IncidentSeverity.info:
        return 'Info';
      case IncidentSeverity.unknown:
        return '—';
    }
  }

  String get raw {
    switch (this) {
      case IncidentSeverity.critical:
        return 'critical';
      case IncidentSeverity.warning:
        return 'warning';
      case IncidentSeverity.info:
        return 'info';
      case IncidentSeverity.unknown:
        return 'info';
    }
  }
}

enum IncidentStatus { open, closed }

extension IncidentStatusX on IncidentStatus {
  static IncidentStatus fromText(String? raw) =>
      raw == 'closed' ? IncidentStatus.closed : IncidentStatus.open;

  bool get isOpen => this == IncidentStatus.open;
}

enum IncidentSource { manual, auto }

extension IncidentSourceX on IncidentSource {
  static IncidentSource fromText(String? raw) =>
      raw == 'auto' ? IncidentSource.auto : IncidentSource.manual;
}

/// Una fila de `v_admin_noc_incidents`.
class NocIncident {
  const NocIncident({
    required this.id,
    required this.type,
    required this.severity,
    this.businessId,
    this.businessName,
    this.environment,
    required this.title,
    this.description,
    this.payload,
    required this.openedAt,
    this.closedAt,
    this.resolvedBy,
    this.resolvedByName,
    this.resolutionNote,
    this.dedupeKey,
    required this.source,
    required this.status,
    required this.ageSeconds,
  });

  final String id;
  final String type;
  final IncidentSeverity severity;
  final String? businessId;
  final String? businessName;
  final BusinessEnvironment? environment;
  final String title;
  final String? description;
  final Map<String, dynamic>? payload;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String? resolvedBy;
  final String? resolvedByName;
  final String? resolutionNote;
  final String? dedupeKey;
  final IncidentSource source;
  final IncidentStatus status;
  final int ageSeconds;

  Duration get age => Duration(seconds: ageSeconds);
  bool get isOpen => status.isOpen;

  factory NocIncident.fromJson(Map<String, dynamic> json) {
    return NocIncident(
      id: json['id'] as String,
      type: (json['type'] as String?) ?? '',
      severity: IncidentSeverityX.fromText(json['severity'] as String?),
      businessId: json['business_id'] as String?,
      businessName: json['business_name'] as String?,
      environment: json['environment'] == null
          ? null
          : BusinessEnvironmentX.fromText(json['environment'] as String?),
      title: (json['title'] as String?) ?? '—',
      description: json['description'] as String?,
      payload: json['payload'] is Map<String, dynamic>
          ? json['payload'] as Map<String, dynamic>
          : null,
      openedAt: parseDate(json['opened_at']) ?? DateTime.now(),
      closedAt: parseDate(json['closed_at']),
      resolvedBy: json['resolved_by'] as String?,
      resolvedByName: json['resolved_by_name'] as String?,
      resolutionNote: json['resolution_note'] as String?,
      dedupeKey: json['dedupe_key'] as String?,
      source: IncidentSourceX.fromText(json['source'] as String?),
      status: IncidentStatusX.fromText(json['status'] as String?),
      ageSeconds: parseInt(json['age_seconds']),
    );
  }
}

/// KPIs del centro de incidentes (`get_admin_incident_summary`).
class IncidentSummary {
  const IncidentSummary({
    required this.openCritical,
    required this.openWarning,
    required this.openInfo,
    required this.openTotal,
    required this.closed24h,
    required this.oldestOpenSeconds,
  });

  final int openCritical;
  final int openWarning;
  final int openInfo;
  final int openTotal;
  final int closed24h;
  final int oldestOpenSeconds;

  factory IncidentSummary.fromJson(Map<String, dynamic> json) {
    return IncidentSummary(
      openCritical: parseInt(json['open_critical']),
      openWarning: parseInt(json['open_warning']),
      openInfo: parseInt(json['open_info']),
      openTotal: parseInt(json['open_total']),
      closed24h: parseInt(json['closed_24h']),
      oldestOpenSeconds: parseInt(json['oldest_open_seconds']),
    );
  }
}

import 'business_environment.dart';

/// Tipo de alerta plataforma. Coincide con `alert_type` del RPC
/// `get_platform_alerts()`.
enum AlertType { agentOffline, ncfCritical, planExpiring, unknown }

extension AlertTypeX on AlertType {
  static AlertType fromText(String? raw) {
    switch (raw) {
      case 'agent_offline':
        return AlertType.agentOffline;
      case 'ncf_critical':
        return AlertType.ncfCritical;
      case 'plan_expiring':
        return AlertType.planExpiring;
      default:
        return AlertType.unknown;
    }
  }
}

enum AlertSeverity { warning, critical }

extension AlertSeverityX on AlertSeverity {
  static AlertSeverity fromText(String? raw) {
    switch (raw) {
      case 'critical':
        return AlertSeverity.critical;
      case 'warning':
      default:
        return AlertSeverity.warning;
    }
  }
}

/// Una alerta del panel de alertas activas.
///
/// Mapea las columnas de `public.get_platform_alerts()`.
class PlatformAlert {
  const PlatformAlert({
    required this.type,
    required this.severity,
    required this.businessId,
    required this.businessName,
    required this.label,
    required this.detail,
    required this.referenceAt,
    required this.environment,
  });

  final AlertType type;
  final AlertSeverity severity;
  final String businessId;
  final String businessName;
  final String label;
  final String detail;
  final DateTime? referenceAt;
  final BusinessEnvironment environment;

  factory PlatformAlert.fromJson(Map<String, dynamic> json) {
    return PlatformAlert(
      type: AlertTypeX.fromText(json['alert_type'] as String?),
      severity: AlertSeverityX.fromText(json['severity'] as String?),
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      label: (json['label'] as String?) ?? '',
      detail: (json['detail'] as String?) ?? '',
      referenceAt: _parseDate(json['reference_at']),
      environment: BusinessEnvironmentX.fromText(json['environment'] as String?),
    );
  }
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

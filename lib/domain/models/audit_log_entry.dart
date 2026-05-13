import '_json_helpers.dart';
import 'business_environment.dart';

enum AuditSeverity { info, warning, critical }

extension AuditSeverityX on AuditSeverity {
  static AuditSeverity fromText(String? raw) {
    switch (raw) {
      case 'critical':
        return AuditSeverity.critical;
      case 'warning':
        return AuditSeverity.warning;
      case 'info':
      default:
        return AuditSeverity.info;
    }
  }
}

/// Una fila de la auditoría plataforma. Mapea las columnas de
/// `get_critical_audit_logs(...)`.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.businessId,
    required this.businessName,
    this.userId,
    this.userName,
    required this.action,
    this.reason,
    this.refTable,
    this.refId,
    required this.severity,
    required this.createdAt,
    required this.environment,
  });

  final String id;
  final String businessId;
  final String businessName;
  final String? userId;
  final String? userName;
  final String action;
  final String? reason;
  final String? refTable;
  final String? refId;
  final AuditSeverity severity;
  final DateTime createdAt;
  final BusinessEnvironment environment;

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      userId: json['user_id'] as String?,
      userName: json['user_name'] as String?,
      action: (json['action'] as String?) ?? '—',
      reason: json['reason'] as String?,
      refTable: json['ref_table'] as String?,
      refId: json['ref_id'] as String?,
      severity: AuditSeverityX.fromText(json['severity'] as String?),
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      environment: BusinessEnvironmentX.fromText(json['environment'] as String?),
    );
  }
}

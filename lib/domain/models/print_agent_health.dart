import '_json_helpers.dart';
import 'business_environment.dart';

enum PrintAgentHealthStatus { online, late, offline, never }

extension PrintAgentHealthStatusX on PrintAgentHealthStatus {
  static PrintAgentHealthStatus fromText(String? raw) {
    switch (raw) {
      case 'ONLINE':
        return PrintAgentHealthStatus.online;
      case 'LATE':
        return PrintAgentHealthStatus.late;
      case 'OFFLINE':
        return PrintAgentHealthStatus.offline;
      case 'NEVER':
      default:
        return PrintAgentHealthStatus.never;
    }
  }

  String get label {
    switch (this) {
      case PrintAgentHealthStatus.online:
        return 'En línea';
      case PrintAgentHealthStatus.late:
        return 'Tardío';
      case PrintAgentHealthStatus.offline:
        return 'Desconectado';
      case PrintAgentHealthStatus.never:
        return 'Sin ping';
    }
  }
}

/// Un agente de impresión con su estado de salud. Mapea `v_admin_print_agents`.
class PrintAgentHealth {
  const PrintAgentHealth({
    required this.agentId,
    required this.businessId,
    required this.businessName,
    required this.environment,
    required this.siteCode,
    this.agentName,
    required this.isActive,
    this.lastSeen,
    this.secondsSinceHeartbeat,
    required this.healthStatus,
  });

  final String agentId;
  final String businessId;
  final String businessName;
  final BusinessEnvironment environment;
  final String siteCode;
  final String? agentName;
  final bool isActive;
  final DateTime? lastSeen;
  final int? secondsSinceHeartbeat;
  final PrintAgentHealthStatus healthStatus;

  factory PrintAgentHealth.fromJson(Map<String, dynamic> json) {
    return PrintAgentHealth(
      agentId: json['agent_id'] as String,
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      environment:
          BusinessEnvironmentX.fromText(json['environment'] as String?),
      siteCode: (json['site_code'] as String?) ?? '',
      agentName: json['agent_name'] as String?,
      isActive: json['is_active'] == true,
      lastSeen: parseDate(json['last_seen']),
      secondsSinceHeartbeat: json['seconds_since_heartbeat'] == null
          ? null
          : parseInt(json['seconds_since_heartbeat']),
      healthStatus:
          PrintAgentHealthStatusX.fromText(json['health_status'] as String?),
    );
  }
}

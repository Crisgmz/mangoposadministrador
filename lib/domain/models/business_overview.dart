import 'business_environment.dart';

/// Estado del agente de impresión de un negocio. Coincide 1:1 con los strings
/// que devuelve `get_platform_overview()` en la columna `agent_status`.
enum AgentStatus { online, late, offline, none }

extension AgentStatusX on AgentStatus {
  static AgentStatus fromText(String? raw) {
    switch (raw) {
      case 'EN LINEA':
        return AgentStatus.online;
      case 'TARDIO':
        return AgentStatus.late;
      case 'DESCONECTADO':
        return AgentStatus.offline;
      case 'SIN AGENTE':
      default:
        return AgentStatus.none;
    }
  }

  String get label {
    switch (this) {
      case AgentStatus.online:
        return 'En línea';
      case AgentStatus.late:
        return 'Tardío';
      case AgentStatus.offline:
        return 'Desconectado';
      case AgentStatus.none:
        return 'Sin agente';
    }
  }
}

/// Actividad del negocio basada en señales de uso reales (login, pago,
/// apertura de caja). Coincide con `activity_status` de la RPC.
enum ActivityStatus { online, late, recent, inactive }

extension ActivityStatusX on ActivityStatus {
  static ActivityStatus fromText(String? raw) {
    switch (raw) {
      case 'EN LINEA':
        return ActivityStatus.online;
      case 'TARDIO':
        return ActivityStatus.late;
      case 'RECIENTE':
        return ActivityStatus.recent;
      case 'INACTIVO':
      default:
        return ActivityStatus.inactive;
    }
  }

  String get label {
    switch (this) {
      case ActivityStatus.online:
        return 'En línea';
      case ActivityStatus.late:
        return 'Tardío';
      case ActivityStatus.recent:
        return 'Hoy';
      case ActivityStatus.inactive:
        return 'Inactivo';
    }
  }
}

/// Estado de las secuencias NCF de un negocio (umbral calculado en el RPC).
enum NcfStatus { ok, warning, critical }

extension NcfStatusX on NcfStatus {
  static NcfStatus fromText(String? raw) {
    switch (raw) {
      case 'CRITICO':
        return NcfStatus.critical;
      case 'ADVERTENCIA':
        return NcfStatus.warning;
      case 'OK':
      default:
        return NcfStatus.ok;
    }
  }
}

/// Plan de membresía actual del negocio.
enum PlanType { trial, free, basic, pro, unknown }

extension PlanTypeX on PlanType {
  static PlanType fromText(String? raw) {
    switch (raw) {
      case 'trial':
        return PlanType.trial;
      case 'free':
        return PlanType.free;
      case 'basic':
        return PlanType.basic;
      case 'pro':
        return PlanType.pro;
      default:
        return PlanType.unknown;
    }
  }

  String get label {
    switch (this) {
      case PlanType.trial:
        return 'Trial';
      case PlanType.free:
        return 'Free';
      case PlanType.basic:
        return 'Basic';
      case PlanType.pro:
        return 'Pro';
      case PlanType.unknown:
        return '—';
    }
  }

  /// Cadena que el backend acepta (`memberships.plan_type`).
  String get raw {
    switch (this) {
      case PlanType.trial:
        return 'trial';
      case PlanType.free:
        return 'free';
      case PlanType.basic:
        return 'basic';
      case PlanType.pro:
        return 'pro';
      case PlanType.unknown:
        return 'basic';
    }
  }
}

/// Una fila del dashboard: un negocio con todas sus métricas del día.
///
/// Mapea exactamente las columnas de `public.get_platform_overview()`.
class BusinessOverview {
  const BusinessOverview({
    required this.id,
    required this.name,
    required this.businessType,
    required this.status,
    required this.domain,
    required this.plan,
    required this.planEndDate,
    required this.agentStatus,
    required this.agentLastSeen,
    required this.agentName,
    required this.salesToday,
    required this.revenueToday,
    required this.ncfAvailable,
    required this.ncfStatus,
    required this.ncfIssuedToday,
    required this.printJobsToday,
    required this.printFailures24h,
    required this.openSessions,
    required this.openTables,
    required this.environment,
    required this.activityStatus,
    this.lastActivityAt,
  });

  final String id;
  final String name;
  final String? businessType;
  final String status; // 'active' | 'inactive'
  final String domain;
  final PlanType plan;
  final DateTime? planEndDate;
  final AgentStatus agentStatus;
  final DateTime? agentLastSeen;
  final String? agentName;
  final int salesToday;
  final double revenueToday;
  final int ncfAvailable;
  final NcfStatus ncfStatus;
  final int ncfIssuedToday;
  final int printJobsToday;
  final int printFailures24h;
  final int openSessions;
  final int openTables;
  final BusinessEnvironment environment;
  final ActivityStatus activityStatus;
  final DateTime? lastActivityAt;

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get isInactive => status == 'inactive';
  bool get isOnline => activityStatus == ActivityStatus.online;
  bool get isProduction => environment == BusinessEnvironment.production;
  bool get isSandbox => environment == BusinessEnvironment.sandbox;

  factory BusinessOverview.fromJson(Map<String, dynamic> json) {
    return BusinessOverview(
      id: json['id'] as String,
      name: (json['business_name'] as String?) ?? '—',
      businessType: json['business_type'] as String?,
      status: (json['status'] as String?) ?? 'active',
      domain: (json['domain'] as String?) ?? '',
      plan: PlanTypeX.fromText(json['plan_type'] as String?),
      planEndDate: _parseDate(json['plan_end_date']),
      agentStatus: AgentStatusX.fromText(json['agent_status'] as String?),
      agentLastSeen: _parseDate(json['agent_last_seen']),
      agentName: json['agent_name'] as String?,
      salesToday: _toInt(json['sales_today']),
      revenueToday: _toDouble(json['revenue_today']),
      ncfAvailable: _toInt(json['ncf_available']),
      ncfStatus: NcfStatusX.fromText(json['ncf_status'] as String?),
      ncfIssuedToday: _toInt(json['ncf_issued_today']),
      printJobsToday: _toInt(json['print_jobs_today']),
      printFailures24h: _toInt(json['print_failures_24h']),
      openSessions: _toInt(json['open_sessions']),
      openTables: _toInt(json['open_tables']),
      environment: BusinessEnvironmentX.fromText(json['environment'] as String?),
      activityStatus:
          ActivityStatusX.fromText(json['activity_status'] as String?),
      lastActivityAt: _parseDate(json['last_activity_at']),
    );
  }
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

int _toInt(dynamic raw) {
  if (raw == null) return 0;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString()) ?? 0;
}

double _toDouble(dynamic raw) {
  if (raw == null) return 0;
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString()) ?? 0;
}

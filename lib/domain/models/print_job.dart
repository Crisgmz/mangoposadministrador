import '_json_helpers.dart';
import 'business_environment.dart';

enum PrintJobStatus { pending, printing, printed, failed, cancelled, unknown }

extension PrintJobStatusX on PrintJobStatus {
  static PrintJobStatus fromText(String? raw) {
    switch (raw) {
      case 'pending':
        return PrintJobStatus.pending;
      case 'printing':
        return PrintJobStatus.printing;
      case 'printed':
        return PrintJobStatus.printed;
      case 'failed':
        return PrintJobStatus.failed;
      case 'cancelled':
        return PrintJobStatus.cancelled;
      default:
        return PrintJobStatus.unknown;
    }
  }

  String get raw {
    switch (this) {
      case PrintJobStatus.pending:
        return 'pending';
      case PrintJobStatus.printing:
        return 'printing';
      case PrintJobStatus.printed:
        return 'printed';
      case PrintJobStatus.failed:
        return 'failed';
      case PrintJobStatus.cancelled:
        return 'cancelled';
      case PrintJobStatus.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case PrintJobStatus.pending:
        return 'Pendiente';
      case PrintJobStatus.printing:
        return 'Imprimiendo';
      case PrintJobStatus.printed:
        return 'Impreso';
      case PrintJobStatus.failed:
        return 'Falló';
      case PrintJobStatus.cancelled:
        return 'Cancelado';
      case PrintJobStatus.unknown:
        return '—';
    }
  }

  bool get isTerminal =>
      this == PrintJobStatus.printed ||
      this == PrintJobStatus.cancelled;
}

/// Un job de impresión enriquecido con info del negocio + impresora.
/// Mapea `v_admin_print_jobs`.
class PrintJob {
  const PrintJob({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.environment,
    this.kind,
    required this.status,
    this.printerId,
    this.printerName,
    required this.ip,
    this.port,
    this.areaCode,
    required this.retryCount,
    required this.priority,
    this.lastError,
    this.error,
    this.nextRetryAt,
    this.claimedAt,
    required this.createdAt,
    this.printedAt,
    required this.ageSeconds,
  });

  final String id;
  final String businessId;
  final String businessName;
  final BusinessEnvironment environment;
  final String? kind;
  final PrintJobStatus status;
  final String? printerId;
  final String? printerName;
  final String ip;
  final int? port;
  final String? areaCode;
  final int retryCount;
  final int priority;
  final String? lastError;
  final String? error;
  final DateTime? nextRetryAt;
  final DateTime? claimedAt;
  final DateTime createdAt;
  final DateTime? printedAt;
  final int ageSeconds;

  /// Mensaje de error preferido — `last_error` primero, `error` legacy si no.
  String? get effectiveError {
    if (lastError != null && lastError!.isNotEmpty) return lastError;
    return error;
  }

  Duration get age => Duration(seconds: ageSeconds);

  factory PrintJob.fromJson(Map<String, dynamic> json) {
    return PrintJob(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      environment:
          BusinessEnvironmentX.fromText(json['environment'] as String?),
      kind: json['kind'] as String?,
      status: PrintJobStatusX.fromText(json['status'] as String?),
      printerId: json['printer_id'] as String?,
      printerName: json['printer_name'] as String?,
      ip: (json['ip'] as String?) ?? '—',
      port: json['port'] == null ? null : parseInt(json['port']),
      areaCode: json['area_code'] as String?,
      retryCount: parseInt(json['retry_count']),
      priority: parseInt(json['priority']),
      lastError: json['last_error'] as String?,
      error: json['error'] as String?,
      nextRetryAt: parseDate(json['next_retry_at']),
      claimedAt: parseDate(json['claimed_at']),
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      printedAt: parseDate(json['printed_at']),
      ageSeconds: parseInt(json['age_seconds']),
    );
  }
}

/// KPIs agregados de impresión (`get_admin_print_health`).
class PrintHealthSummary {
  const PrintHealthSummary({
    required this.agentsTotal,
    required this.agentsOnline,
    required this.agentsLate,
    required this.agentsOffline,
    required this.jobsPending,
    required this.jobsPrinting,
    required this.jobsFailed1h,
    required this.jobsPrinted1h,
  });

  final int agentsTotal;
  final int agentsOnline;
  final int agentsLate;
  final int agentsOffline;
  final int jobsPending;
  final int jobsPrinting;
  final int jobsFailed1h;
  final int jobsPrinted1h;

  factory PrintHealthSummary.fromJson(Map<String, dynamic> json) {
    return PrintHealthSummary(
      agentsTotal: parseInt(json['agents_total']),
      agentsOnline: parseInt(json['agents_online']),
      agentsLate: parseInt(json['agents_late']),
      agentsOffline: parseInt(json['agents_offline']),
      jobsPending: parseInt(json['jobs_pending']),
      jobsPrinting: parseInt(json['jobs_printing']),
      jobsFailed1h: parseInt(json['jobs_failed_1h']),
      jobsPrinted1h: parseInt(json['jobs_printed_1h']),
    );
  }
}

/// Una fila del ranking de top negocios con más fallas (`get_admin_top_print_failures`).
class PrintFailureRanking {
  const PrintFailureRanking({
    required this.businessId,
    required this.businessName,
    required this.environment,
    required this.failedCount,
    this.lastFailedAt,
  });

  final String businessId;
  final String businessName;
  final BusinessEnvironment environment;
  final int failedCount;
  final DateTime? lastFailedAt;

  factory PrintFailureRanking.fromJson(Map<String, dynamic> json) {
    return PrintFailureRanking(
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      environment:
          BusinessEnvironmentX.fromText(json['environment'] as String?),
      failedCount: parseInt(json['failed_count']),
      lastFailedAt: parseDate(json['last_failed_at']),
    );
  }
}

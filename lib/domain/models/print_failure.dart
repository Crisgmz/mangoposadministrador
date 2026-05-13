import '_json_helpers.dart';
import 'business_environment.dart';

/// Una falla de impresión reciente. Mapea `get_recent_print_failures(...)`.
class PrintFailure {
  const PrintFailure({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.printerIp,
    this.printerPort,
    required this.printerName,
    required this.status,
    this.error,
    required this.createdAt,
    required this.environment,
  });

  final String id;
  final String businessId;
  final String businessName;
  final String printerIp;
  final int? printerPort;
  final String printerName;
  final String status;
  final String? error;
  final DateTime createdAt;
  final BusinessEnvironment environment;

  factory PrintFailure.fromJson(Map<String, dynamic> json) {
    return PrintFailure(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      printerIp: (json['printer_ip'] as String?) ?? '—',
      printerPort: parseInt(json['printer_port'], fallback: 0) == 0
          ? null
          : parseInt(json['printer_port']),
      printerName: (json['printer_name'] as String?) ?? '—',
      status: (json['status'] as String?) ?? 'failed',
      error: json['error'] as String?,
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      environment: BusinessEnvironmentX.fromText(json['environment'] as String?),
    );
  }
}

import '_json_helpers.dart';
import 'business_environment.dart';

/// KPIs agregados de salud fiscal (`get_admin_fiscal_health`).
class FiscalHealthSummary {
  const FiscalHealthSummary({
    required this.ecfStuck,
    required this.ecfRejected24h,
    required this.ecfEmittedToday,
    required this.cancelledToday,
    required this.ncfSequencesTotal,
    required this.ncfCritical,
    required this.ncfWarning,
    required this.ncfExpiring,
    required this.ncfExpired,
  });

  final int ecfStuck;
  final int ecfRejected24h;
  final int ecfEmittedToday;
  final int cancelledToday;
  final int ncfSequencesTotal;
  final int ncfCritical;
  final int ncfWarning;
  final int ncfExpiring;
  final int ncfExpired;

  factory FiscalHealthSummary.fromJson(Map<String, dynamic> json) {
    return FiscalHealthSummary(
      ecfStuck: parseInt(json['ecf_stuck']),
      ecfRejected24h: parseInt(json['ecf_rejected_24h']),
      ecfEmittedToday: parseInt(json['ecf_emitted_today']),
      cancelledToday: parseInt(json['cancelled_today']),
      ncfSequencesTotal: parseInt(json['ncf_sequences_total']),
      ncfCritical: parseInt(json['ncf_critical']),
      ncfWarning: parseInt(json['ncf_warning']),
      ncfExpiring: parseInt(json['ncf_expiring']),
      ncfExpired: parseInt(json['ncf_expired']),
    );
  }
}

/// Tipo de problema en un fiscal_document.
enum FiscalProblemKind { stuck, rejected, cancelled, ok }

extension FiscalProblemKindX on FiscalProblemKind {
  static FiscalProblemKind fromText(String? raw) {
    switch (raw) {
      case 'STUCK':
        return FiscalProblemKind.stuck;
      case 'REJECTED':
        return FiscalProblemKind.rejected;
      case 'CANCELLED':
        return FiscalProblemKind.cancelled;
      case 'OK':
      default:
        return FiscalProblemKind.ok;
    }
  }

  String get label {
    switch (this) {
      case FiscalProblemKind.stuck:
        return 'Stuck';
      case FiscalProblemKind.rejected:
        return 'Rechazado';
      case FiscalProblemKind.cancelled:
        return 'Anulado';
      case FiscalProblemKind.ok:
        return 'OK';
    }
  }
}

/// Una fila de `v_admin_fiscal_problems` — un documento fiscal que requiere
/// atención del NOC.
class FiscalProblem {
  const FiscalProblem({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.environment,
    required this.ncfNumber,
    required this.ncfType,
    required this.customerName,
    this.customerRnc,
    required this.total,
    required this.itbisAmount,
    required this.isElectronic,
    this.ecfStatus,
    this.ecfTrackingNumber,
    required this.fiscalStatus,
    this.cancellationReason,
    required this.issuedAt,
    this.ecfSignedAt,
    required this.problemKind,
    required this.ageSeconds,
  });

  final String id;
  final String businessId;
  final String businessName;
  final BusinessEnvironment environment;
  final String ncfNumber;
  final String ncfType;
  final String customerName;
  final String? customerRnc;
  final double total;
  final double itbisAmount;
  final bool isElectronic;
  final String? ecfStatus;
  final String? ecfTrackingNumber;
  final String fiscalStatus;
  final String? cancellationReason;
  final DateTime issuedAt;
  final DateTime? ecfSignedAt;
  final FiscalProblemKind problemKind;
  final int ageSeconds;

  factory FiscalProblem.fromJson(Map<String, dynamic> json) {
    return FiscalProblem(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      environment:
          BusinessEnvironmentX.fromText(json['environment'] as String?),
      ncfNumber: (json['ncf_number'] as String?) ?? '—',
      ncfType: (json['ncf_type'] as String?) ?? '',
      customerName: (json['customer_name'] as String?) ?? '—',
      customerRnc: json['customer_rnc'] as String?,
      total: parseDouble(json['total']),
      itbisAmount: parseDouble(json['itbis_amount']),
      isElectronic: json['is_electronic'] == true,
      ecfStatus: json['ecf_status'] as String?,
      ecfTrackingNumber: json['ecf_tracking_number'] as String?,
      fiscalStatus: (json['fiscal_status'] as String?) ?? 'active',
      cancellationReason: json['cancellation_reason'] as String?,
      issuedAt: parseDate(json['issued_at']) ?? DateTime.now(),
      ecfSignedAt: parseDate(json['ecf_signed_at']),
      problemKind:
          FiscalProblemKindX.fromText(json['problem_kind'] as String?),
      ageSeconds: parseInt(json['age_seconds']),
    );
  }
}

/// Estado de salud de una secuencia NCF.
enum NcfHealthStatus { ok, warning, critical, expiringSoon, expired, inactive }

extension NcfHealthStatusX on NcfHealthStatus {
  static NcfHealthStatus fromText(String? raw) {
    switch (raw) {
      case 'CRITICAL':
        return NcfHealthStatus.critical;
      case 'WARNING':
        return NcfHealthStatus.warning;
      case 'EXPIRING_SOON':
        return NcfHealthStatus.expiringSoon;
      case 'EXPIRED':
        return NcfHealthStatus.expired;
      case 'INACTIVE':
        return NcfHealthStatus.inactive;
      case 'OK':
      default:
        return NcfHealthStatus.ok;
    }
  }

  String get label {
    switch (this) {
      case NcfHealthStatus.ok:
        return 'OK';
      case NcfHealthStatus.warning:
        return 'Bajo';
      case NcfHealthStatus.critical:
        return 'Crítico';
      case NcfHealthStatus.expiringSoon:
        return 'Vence pronto';
      case NcfHealthStatus.expired:
        return 'Vencida';
      case NcfHealthStatus.inactive:
        return 'Inactiva';
    }
  }
}

/// Una secuencia NCF con su estado de disponibilidad y vencimiento.
class NcfSequenceStatus {
  const NcfSequenceStatus({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.environment,
    required this.ncfType,
    required this.serie,
    required this.prefix,
    required this.rangeStart,
    required this.rangeEnd,
    required this.currentNumber,
    required this.available,
    this.expirationDate,
    required this.isActive,
    this.authorizedBy,
    required this.healthStatus,
  });

  final String id;
  final String businessId;
  final String businessName;
  final BusinessEnvironment environment;
  final String ncfType;
  final String serie;
  final String prefix;
  final int rangeStart;
  final int rangeEnd;
  final int currentNumber;
  final int available;
  final DateTime? expirationDate;
  final bool isActive;
  final String? authorizedBy;
  final NcfHealthStatus healthStatus;

  /// % consumido del rango (0.0 - 1.0).
  double get consumedRatio {
    final total = rangeEnd - rangeStart + 1;
    if (total <= 0) return 1.0;
    final used = (currentNumber - rangeStart).clamp(0, total);
    return used / total;
  }

  factory NcfSequenceStatus.fromJson(Map<String, dynamic> json) {
    return NcfSequenceStatus(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      environment:
          BusinessEnvironmentX.fromText(json['environment'] as String?),
      ncfType: (json['ncf_type'] as String?) ?? '',
      serie: (json['serie'] as String?) ?? '',
      prefix: (json['prefix'] as String?) ?? '',
      rangeStart: parseInt(json['range_start']),
      rangeEnd: parseInt(json['range_end']),
      currentNumber: parseInt(json['current_number']),
      available: parseInt(json['available']),
      expirationDate: parseDate(json['expiration_date']),
      isActive: json['is_active'] == true,
      authorizedBy: json['authorized_by'] as String?,
      healthStatus:
          NcfHealthStatusX.fromText(json['health_status'] as String?),
    );
  }
}

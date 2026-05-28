/// Una fila de `admin_list_pending_businesses` — un negocio en
/// `status='pending'` con sus datos joineados (owner, plan, método de pago).
class PendingBusiness {
  const PendingBusiness({
    required this.businessId,
    required this.businessName,
    required this.status,
    required this.createdAt,
    required this.hasVerifiedCard,
    this.branchName,
    this.businessType,
    this.country,
    this.address,
    this.phone,
    this.domain,
    this.ownerId,
    this.ownerEmail,
    this.ownerFullName,
    this.emailConfirmedAt,
    this.lastSignInAt,
    this.planCode,
    this.planName,
    this.planMonthlyPrice,
    this.membershipBillingStatus,
    this.trialEndsAt,
    this.nextBillingDate,
  });

  final String businessId;
  final String businessName;
  final String? branchName;
  final String? businessType;
  final String? country;
  final String? address;
  final String? phone;
  final String? domain;
  final String status;
  final DateTime createdAt;
  final String? ownerId;
  final String? ownerEmail;
  final String? ownerFullName;
  final DateTime? emailConfirmedAt;
  final DateTime? lastSignInAt;
  final String? planCode;
  final String? planName;
  final double? planMonthlyPrice;
  final String? membershipBillingStatus;
  final DateTime? trialEndsAt;
  final DateTime? nextBillingDate;
  final bool hasVerifiedCard;

  /// Nombre del owner para mostrar — fallback a email, después a primer
  /// segmento del UUID si no hay nada.
  String get ownerDisplayName {
    final n = ownerFullName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    final e = ownerEmail?.trim() ?? '';
    if (e.isNotEmpty) return e;
    if (ownerId != null && ownerId!.isNotEmpty) {
      return ownerId!.substring(0, 8);
    }
    return '—';
  }

  /// Días restantes de trial (puede ser negativo si ya venció).
  int? get trialDaysLeft {
    if (trialEndsAt == null) return null;
    final diff = trialEndsAt!.difference(DateTime.now());
    return diff.inDays;
  }

  bool get emailVerified => emailConfirmedAt != null;

  factory PendingBusiness.fromJson(Map<String, dynamic> json) {
    return PendingBusiness(
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      branchName: json['branch_name'] as String?,
      businessType: json['business_type'] as String?,
      country: json['country'] as String?,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      domain: json['domain'] as String?,
      status: (json['status'] as String?) ?? 'pending',
      createdAt: _date(json['created_at']) ?? DateTime.now(),
      ownerId: json['owner_id'] as String?,
      ownerEmail: json['owner_email'] as String?,
      ownerFullName: json['owner_full_name'] as String?,
      emailConfirmedAt: _date(json['email_confirmed_at']),
      lastSignInAt: _date(json['last_sign_in_at']),
      planCode: json['plan_code'] as String?,
      planName: json['plan_name'] as String?,
      planMonthlyPrice: _toDouble(json['plan_monthly_price']),
      membershipBillingStatus: json['membership_billing_status'] as String?,
      trialEndsAt: _date(json['trial_ends_at']),
      nextBillingDate: _date(json['next_billing_date']),
      hasVerifiedCard: (json['has_verified_card'] as bool?) ?? false,
    );
  }
}

DateTime? _date(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

double? _toDouble(dynamic raw) {
  if (raw == null) return null;
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}

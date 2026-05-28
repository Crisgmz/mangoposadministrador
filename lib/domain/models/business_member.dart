/// Fila de la respuesta de `admin_get_business_team`. Representa un miembro
/// (owner o staff) del negocio con sus datos de contacto.
class BusinessMember {
  const BusinessMember({
    required this.userId,
    required this.isOwner,
    required this.role,
    required this.status,
    this.membershipId,
    this.email,
    this.emailConfirmedAt,
    this.fullName,
    this.phone,
    this.lastSignInAt,
    this.userCreatedAt,
    this.membershipCreatedAt,
    this.planType,
    this.endDate,
  });

  final String userId;
  final String? membershipId;
  final bool isOwner;
  final String role;
  final String status;
  final String? email;
  final DateTime? emailConfirmedAt;
  final String? fullName;
  final String? phone;
  final DateTime? lastSignInAt;
  final DateTime? userCreatedAt;
  final DateTime? membershipCreatedAt;
  final String? planType;
  final DateTime? endDate;

  bool get emailVerified => emailConfirmedAt != null;

  /// Nombre mostrable. Si no hay full_name, cae al email; si tampoco,
  /// muestra los primeros 8 chars del user_id.
  String get displayName {
    final n = fullName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    final e = email?.trim() ?? '';
    if (e.isNotEmpty) return e;
    return userId.substring(0, 8);
  }

  factory BusinessMember.fromJson(Map<String, dynamic> json) {
    return BusinessMember(
      userId: json['user_id'] as String,
      membershipId: json['membership_id'] as String?,
      isOwner: (json['is_owner'] as bool?) ?? false,
      role: (json['role'] as String?) ?? 'member',
      status: (json['status'] as String?) ?? 'active',
      email: json['email'] as String?,
      emailConfirmedAt: _date(json['email_confirmed_at']),
      fullName: json['full_name'] as String?,
      phone: json['phone'] as String?,
      lastSignInAt: _date(json['last_sign_in_at']),
      userCreatedAt: _date(json['user_created_at']),
      membershipCreatedAt: _date(json['membership_created_at']),
      planType: json['plan_type'] as String?,
      endDate: _date(json['end_date']),
    );
  }
}

DateTime? _date(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

/// Fila de `plan_catalog` enriquecida con `active_subscribers` (vía `get_plans`).
class Plan {
  const Plan({
    required this.code,
    required this.name,
    required this.priceMonthly,
    required this.currencyCode,
    required this.features,
    required this.displayOrder,
    required this.isActive,
    required this.taxIncluded,
    required this.activeSubscribers,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.archivedAt,
    this.archivedReason,
  });

  final String code;
  final String name;
  final String? description;
  final double priceMonthly;
  final String currencyCode;
  final List<String> features;
  final int displayOrder;
  final bool isActive;
  /// Si true, `priceMonthly` ya incluye ITBIS y la factura no desglosa impuesto.
  final bool taxIncluded;
  final DateTime? archivedAt;
  final String? archivedReason;
  final int activeSubscribers;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isArchived => archivedAt != null;

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      code: json['code'] as String,
      name: (json['name'] as String?) ?? '',
      description: json['description'] as String?,
      priceMonthly: _toDouble(json['price_monthly']),
      currencyCode: (json['currency_code'] as String?) ?? 'DOP',
      features: _toStringList(json['features']),
      displayOrder: _toInt(json['display_order']),
      isActive: (json['is_active'] as bool?) ?? true,
      taxIncluded: (json['tax_included'] as bool?) ?? true,
      archivedAt: _parseDate(json['archived_at']),
      archivedReason: json['archived_reason'] as String?,
      activeSubscribers: _toInt(json['active_subscribers']),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }
}

double _toDouble(dynamic raw) {
  if (raw == null) return 0;
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString()) ?? 0;
}

int _toInt(dynamic raw) {
  if (raw == null) return 0;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString()) ?? 0;
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

List<String> _toStringList(dynamic raw) {
  if (raw == null) return const [];
  if (raw is List) return raw.map((e) => e.toString()).toList(growable: false);
  return const [];
}

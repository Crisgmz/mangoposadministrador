/// Facturas electrónicas incluidas y uso de un negocio, tal como lo devuelve
/// `admin_get_ecf_usage` (migración 0051).
///
/// Las e-CF que la DGII acepta por encima de lo incluido en un período se
/// cobran a un precio por unidad y se suman a la mensualidad siguiente.
class EcfQuotaUsage {
  const EcfQuotaUsage({
    required this.hasQuota,
    required this.globalPriceCents,
    required this.unitPriceCents,
    required this.current,
    required this.last30Days,
    this.included,
    this.priceOverrideCents,
    this.countingSince,
    this.notes,
    this.nextChargeDate,
    this.history = const [],
  });

  /// Sin cantidad configurada, las e-CF no se cobran aparte.
  final bool hasQuota;

  /// e-CF incluidas por período de cobro.
  final int? included;

  /// Precio propio del negocio por e-CF extra, en centavos. `null` = global.
  final int? priceOverrideCents;

  /// Precio global (Configuración). 0 = todavía no definido.
  final int globalPriceCents;

  /// Precio que se aplica: el propio o, si no hay, el global.
  final int unitPriceCents;

  /// Desde cuándo se cuentan (la primera vez que se fijó la cantidad).
  final DateTime? countingSince;
  final String? notes;
  final DateTime? nextChargeDate;

  /// Período en curso: lo aceptado desde lo último cobrado hasta hoy.
  final EcfWindow current;

  /// Aceptadas en los últimos 30 días (referencia cuando no hay cantidad).
  final int last30Days;

  /// Últimos períodos ya cobrados, del más reciente al más viejo.
  final List<EcfWindow> history;

  bool get priceIsCustom => priceOverrideCents != null;

  factory EcfQuotaUsage.fromJson(Map<String, dynamic> json) {
    final rawCurrent = json['current'];
    final rawHistory = json['history'];
    return EcfQuotaUsage(
      hasQuota: json['has_quota'] == true,
      included: json['included'] == null ? null : _toInt(json['included']),
      priceOverrideCents: json['price_override_cents'] == null
          ? null
          : _toInt(json['price_override_cents']),
      globalPriceCents: _toInt(json['global_price_cents']),
      unitPriceCents: _toInt(json['unit_price_cents']),
      countingSince: _parseDate(json['counting_since']),
      notes: json['notes'] as String?,
      nextChargeDate: _parseDate(json['next_charge_date']),
      current: rawCurrent is Map
          ? EcfWindow.fromJson(Map<String, dynamic>.from(rawCurrent))
          : const EcfWindow(),
      last30Days: _toInt(json['last_30_days']),
      history: rawHistory is List
          ? rawHistory
                .whereType<Map>()
                .map((h) => EcfWindow.fromJson(Map<String, dynamic>.from(h)))
                .toList(growable: false)
          : const [],
    );
  }
}

/// Uso de e-CF en una ventana de tiempo (un período de cobro).
class EcfWindow {
  const EcfWindow({
    this.used = 0,
    this.extra = 0,
    this.overageCents = 0,
    this.usageFrom,
    this.usageTo,
    this.periodStart,
    this.source,
  });

  /// Aceptadas por la DGII en la ventana.
  final int used;

  /// Por encima de lo incluido.
  final int extra;
  final int overageCents;
  final DateTime? usageFrom;
  final DateTime? usageTo;

  /// Solo historial: período del cobro o factura que lo cobró.
  final DateTime? periodStart;

  /// Solo historial: `card` (cobro con tarjeta) o `invoice` (factura manual).
  final String? source;

  factory EcfWindow.fromJson(Map<String, dynamic> json) {
    return EcfWindow(
      used: _toInt(json['used']),
      extra: _toInt(json['extra']),
      overageCents: _toInt(json['overage_cents']),
      usageFrom: _parseDate(json['usage_from']),
      usageTo: _parseDate(json['usage_to']),
      periodStart: _parseDate(json['period_start']),
      source: json['source'] as String?,
    );
  }
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

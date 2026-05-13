/// Un punto horario de la serie de ingresos plataforma (últimas 12 h).
///
/// Mapea las columnas de `public.get_revenue_trend_12h()`.
class RevenueHour {
  const RevenueHour({
    required this.hour,
    required this.label,
    required this.revenue,
    required this.transactions,
  });

  final DateTime hour;
  final String label; // 'HH:MM' en hora de Santo Domingo
  final double revenue;
  final int transactions;

  factory RevenueHour.fromJson(Map<String, dynamic> json) {
    return RevenueHour(
      hour: DateTime.parse(json['hour'].toString()),
      label: (json['hour_label'] as String?) ?? '',
      revenue: _toDouble(json['revenue']),
      transactions: _toInt(json['transactions']),
    );
  }
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

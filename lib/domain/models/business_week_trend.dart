import '_json_helpers.dart';
import 'business_environment.dart';

/// Tendencia semanal de ingresos por negocio (`get_business_week_trend()`).
class BusinessWeekTrend {
  const BusinessWeekTrend({
    required this.businessId,
    required this.businessName,
    required this.weekRevenue,
    required this.lastWeekRevenue,
    required this.trendPct,
    required this.environment,
  });

  final String businessId;
  final String businessName;
  final double weekRevenue;
  final double lastWeekRevenue;
  final double trendPct;
  final BusinessEnvironment environment;

  factory BusinessWeekTrend.fromJson(Map<String, dynamic> json) {
    return BusinessWeekTrend(
      businessId: json['business_id'] as String,
      businessName: (json['business_name'] as String?) ?? '—',
      weekRevenue: parseDouble(json['week_revenue']),
      lastWeekRevenue: parseDouble(json['last_week_revenue']),
      trendPct: parseDouble(json['trend_pct']),
      environment: BusinessEnvironmentX.fromText(json['environment'] as String?),
    );
  }
}

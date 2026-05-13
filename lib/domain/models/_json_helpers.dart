/// Helpers compartidos para parsear JSON proveniente de Supabase
/// (numéricos como String, fechas ISO, etc).
library;

DateTime? parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}

int parseInt(dynamic raw, {int fallback = 0}) {
  if (raw == null) return fallback;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString()) ?? fallback;
}

double parseDouble(dynamic raw, {double fallback = 0}) {
  if (raw == null) return fallback;
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString()) ?? fallback;
}

import 'package:intl/intl.dart';

// Formato fijo "RD$ 13,000.00":
//   - Símbolo SIEMPRE al inicio: "RD$ ".
//   - Coma como separador de miles, punto como separador decimal.
// `NumberFormat.currency(locale: 'es_DO')` invierte ambos (símbolo al final
// y "." de miles), por eso usamos un patrón explícito con locale en_US.
final NumberFormat _amount = NumberFormat('#,##0.00', 'en_US');
final NumberFormat _amountCompact = NumberFormat('#,##0', 'en_US');
final NumberFormat _intFmt = NumberFormat('#,##0', 'en_US');

/// Formatea un monto en pesos dominicanos (DOP) con dos decimales.
/// Ej: `38420.5` → `RD$ 38,420.50`.
String formatRd(num value) => 'RD\$ ${_amount.format(value)}';

/// Versión sin decimales — usar solo cuando el ancho del componente lo exija.
String formatRdCompact(num value) => 'RD\$ ${_amountCompact.format(value)}';

/// Alias histórico — equivalente a `formatRd` (con 2 decimales).
String formatRdPrecise(num value) => formatRd(value);

/// Versión abreviada para KPIs donde el ancho es de una celda: `RD$ 458.9k`,
/// `RD$ 1.2M`. Por debajo de mil no abrevia — "RD$ 0.9k" se lee peor que
/// "RD$ 900".
String formatRdShort(num value) {
  final v = value.toDouble();
  final abs = v.abs();
  if (abs >= 1000000) {
    return 'RD\$ ${(v / 1000000).toStringAsFixed(1)}M';
  }
  if (abs >= 1000) {
    return 'RD\$ ${(v / 1000).toStringAsFixed(1)}k';
  }
  return formatRdCompact(v);
}

/// Formatea un entero con separadores de miles (`1820` → `1,820`).
String formatInt(num value) => _intFmt.format(value);

/// "hace 5 min", "hace 2 h", "hace 3 d".
/// Devuelve `'—'` para `null` o fechas inválidas.
String formatRelative(DateTime? when) {
  if (when == null) return '—';
  final diff = DateTime.now().difference(when);
  final s = diff.inSeconds;
  if (s < 0) return 'en breve';
  if (s < 60) return 'hace ${s}s';
  final m = diff.inMinutes;
  if (m < 60) return 'hace $m min';
  final h = diff.inHours;
  if (h < 24) return 'hace $h h';
  final d = diff.inDays;
  return 'hace $d d';
}

/// Días enteros entre `now()` y la fecha dada. Negativo si la fecha pasó.
int daysUntil(DateTime? when) {
  if (when == null) return 0;
  return when.difference(DateTime.now()).inDays;
}

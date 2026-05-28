class VpsMetrics {
  const VpsMetrics({
    this.cpuPercent,
    this.memoryUsedMb,
    this.diskUsedGb,
    this.bandwidthUsedGb,
    this.uptimeSeconds,
  });

  final double? cpuPercent;
  final double? memoryUsedMb;
  final double? diskUsedGb;
  final double? bandwidthUsedGb;
  final double? uptimeSeconds;

  /// Uptime formateado humano (ej: "27d 12h", "3h 45m"). Null si no hay dato.
  String? get uptimeHuman {
    if (uptimeSeconds == null || uptimeSeconds! <= 0) return null;
    final total = uptimeSeconds!.toInt();
    final days = total ~/ 86400;
    final hours = (total % 86400) ~/ 3600;
    final mins = (total % 3600) ~/ 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  factory VpsMetrics.fromJson(Map<String, dynamic> json) {
    return VpsMetrics(
      cpuPercent: _num(json['cpu_percent']),
      memoryUsedMb: _num(json['memory_used_mb']),
      diskUsedGb: _num(json['disk_used_gb']),
      bandwidthUsedGb: _num(json['bandwidth_used_gb']),
      uptimeSeconds: _num(json['uptime_seconds']),
    );
  }
}

class VpsInstance {
  const VpsInstance({
    required this.id,
    required this.hostname,
    required this.state,
    this.ipAddress,
    this.region,
    this.cpuCores,
    this.memoryMb,
    this.diskGb,
    this.plan,
    this.template,
    this.metrics,
  });

  final int id;
  final String hostname;
  final String state; // running / stopped / ...
  final String? ipAddress;
  final String? region;
  final int? cpuCores;
  final int? memoryMb;
  final int? diskGb;
  final String? plan;
  final String? template; // ej: "Ubuntu 24.04 with Coolify"
  final VpsMetrics? metrics;

  bool get isRunning => state.toLowerCase() == 'running';

  factory VpsInstance.fromJson(Map<String, dynamic> json) {
    return VpsInstance(
      id: (json['id'] as num).toInt(),
      hostname: _str(json['hostname']) ?? 'vps-${json['id']}',
      state: _str(json['state']) ?? 'unknown',
      ipAddress: _str(json['ip_address']),
      region: _str(json['region']),
      cpuCores: _int(json['cpu_cores']),
      memoryMb: _int(json['memory_mb']),
      diskGb: _int(json['disk_gb']),
      plan: _str(json['plan']),
      template: _str(json['template']),
      metrics: json['metrics'] == null
          ? null
          : VpsMetrics.fromJson(json['metrics'] as Map<String, dynamic>),
    );
  }
}

/// Cast seguro a String. Si el valor no es String (lista, mapa, número), lo
/// stringifica o devuelve null. Evita TypeError cuando la API upstream
/// devuelve un shape inesperado (ej: `ipv4_addresses` como List en vez de
/// String).
String? _str(dynamic raw) {
  if (raw == null) return null;
  if (raw is String) return raw.isEmpty ? null : raw;
  if (raw is List) {
    if (raw.isEmpty) return null;
    final first = raw.first;
    if (first is String) return first;
    if (first is Map) {
      // Caso típico: [{ "address": "1.2.3.4", "primary": true }]
      final v = first['address'] ?? first['ip'] ?? first['value'];
      return v?.toString();
    }
    return first.toString();
  }
  return raw.toString();
}

double? _num(dynamic raw) {
  if (raw == null) return null;
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}

int? _int(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}

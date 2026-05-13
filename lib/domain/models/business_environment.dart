/// Entorno de un negocio: `production` (cliente real) o `sandbox` (cuenta
/// de prueba interna). Se persiste en `businesses.environment`.
enum BusinessEnvironment { production, sandbox }

extension BusinessEnvironmentX on BusinessEnvironment {
  /// Cadena que se manda/recibe del backend.
  String get raw {
    switch (this) {
      case BusinessEnvironment.production:
        return 'production';
      case BusinessEnvironment.sandbox:
        return 'sandbox';
    }
  }

  /// Texto humano para UI (es-DO).
  String get label {
    switch (this) {
      case BusinessEnvironment.production:
        return 'Producción';
      case BusinessEnvironment.sandbox:
        return 'Sandbox';
    }
  }

  String get shortLabel {
    switch (this) {
      case BusinessEnvironment.production:
        return 'PROD';
      case BusinessEnvironment.sandbox:
        return 'SBX';
    }
  }

  static BusinessEnvironment fromText(String? raw) {
    if (raw == 'sandbox') return BusinessEnvironment.sandbox;
    return BusinessEnvironment.production;
  }
}

/// Datos del emisor (MangoPOS) que aparecen en facturas y comunicación.
/// Espejo de `public.company_settings` (single-row enforced).
class CompanySettings {
  const CompanySettings({
    required this.legalName,
    this.rnc,
    this.address,
    this.city,
    this.country,
    this.phone,
    this.email,
    this.website,
    this.logoUrl,
    this.paymentInstructions,
    this.updatedAt,
    this.ecfOveragePriceCents = 0,
  });

  final String legalName;
  final String? rnc;
  final String? address;
  final String? city;
  final String? country;
  final String? phone;
  final String? email;
  final String? website;
  final String? logoUrl;
  final String? paymentInstructions;
  final DateTime? updatedAt;

  /// Precio global por factura electrónica extra, en centavos (migración
  /// 0051). 0 = el extra no se cobra.
  final int ecfOveragePriceCents;

  /// Concatena `address` + `city` para mostrar en una sola línea.
  String? get fullAddress {
    final parts = <String>[
      if (address != null && address!.isNotEmpty) address!,
      if (city != null && city!.isNotEmpty) city!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  factory CompanySettings.fromJson(Map<String, dynamic> json) {
    return CompanySettings(
      legalName: (json['legal_name'] as String?) ?? 'MangoPOS',
      rnc: json['rnc'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      website: json['website'] as String?,
      logoUrl: json['logo_url'] as String?,
      paymentInstructions: json['payment_instructions'] as String?,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'].toString()),
      ecfOveragePriceCents:
          (json['ecf_overage_price_cents'] as num?)?.toInt() ?? 0,
    );
  }

  /// Fallback con los valores que estaban hardcoded en `_Issuer` (por si
  /// el RPC falla — el PDF debe poder generarse igual).
  static const fallback = CompanySettings(
    legalName: 'MangoPOS Servicios SRL',
    rnc: '1-31-23456-7',
    address: 'Av. Lope de Vega No. 13, Naco',
    city: 'Santo Domingo, RD',
    phone: '+1 (809) 555-0100',
    email: 'soporte@mangopos.do',
    website: 'mangopos.do',
    paymentInstructions:
        'Métodos aceptados: transferencia bancaria, efectivo o tarjeta.\n'
        'Confirmar pago vía WhatsApp o email a soporte@mangopos.do.',
  );
}

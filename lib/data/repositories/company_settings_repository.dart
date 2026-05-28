import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../domain/models/company_settings.dart';

class CompanySettingsRepository {
  CompanySettingsRepository(this._client);

  final SupabaseClient _client;

  static const String _bucket = 'company-assets';

  /// Sube el logo al bucket `company-assets` y devuelve la URL pública.
  /// Si ya existía un logo, se reemplaza (upsert con el mismo path).
  Future<String> uploadLogo({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
  }) async {
    // Path único por archivo para evitar caché agresivo de CDN al reemplazar.
    final ext = filename.split('.').last.toLowerCase();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'logo_$stamp.$ext';

    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: true,
            contentType: mimeType,
          ),
        );

    return _client.storage.from(_bucket).getPublicUrl(path);
  }

  Future<CompanySettings> get() async {
    final raw = await _client.rpc('admin_get_company_settings');
    if (raw is Map<String, dynamic>) {
      return CompanySettings.fromJson(raw);
    }
    if (raw is List && raw.isNotEmpty) {
      return CompanySettings.fromJson(raw.first as Map<String, dynamic>);
    }
    return CompanySettings.fallback;
  }

  Future<CompanySettings> update({
    required String legalName,
    String? rnc,
    String? address,
    String? city,
    String? country,
    String? phone,
    String? email,
    String? website,
    String? logoUrl,
    String? paymentInstructions,
  }) async {
    final raw = await _client.rpc(
      'admin_update_company_settings',
      params: {
        'p_legal_name': legalName,
        'p_rnc': rnc,
        'p_address': address,
        'p_city': city,
        'p_country': country,
        'p_phone': phone,
        'p_email': email,
        'p_website': website,
        'p_logo_url': logoUrl,
        'p_payment_instructions': paymentInstructions,
      },
    );
    if (raw is Map<String, dynamic>) {
      return CompanySettings.fromJson(raw);
    }
    if (raw is List && raw.isNotEmpty) {
      return CompanySettings.fromJson(raw.first as Map<String, dynamic>);
    }
    return CompanySettings.fallback;
  }
}

final companySettingsRepositoryProvider =
    Provider<CompanySettingsRepository>((ref) {
  return CompanySettingsRepository(ref.watch(supabaseProvider));
});

/// Datos de la empresa. Cached con autoDispose=false para que cuando el PDF
/// los necesite siempre estén listos (es solo una row).
final companySettingsProvider = FutureProvider<CompanySettings>((ref) {
  return ref.watch(companySettingsRepositoryProvider).get();
});

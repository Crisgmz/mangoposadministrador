import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../domain/models/external_ecf_request.dart';

/// Bandeja de solicitudes de facturación electrónica que llegan de otras apps
/// que comparten esta cuenta de Alanube (hoy Busi Pos Web).
///
/// A diferencia del resto del alta e-CF, esto NO pasa por una Edge Function:
/// la tabla `external_ecf_requests` (migración 20260926_0001 del repo
/// mangospos) se lee y se actualiza directo, con la RLS exigiendo
/// `is_platform_operator()`. No hace falta más: acá no se toca Alanube ni la
/// base de la app de origen, solo el seguimiento interno.
class ExternalEcfRequestsRepository {
  ExternalEcfRequestsRepository(this._client);

  final SupabaseClient _client;

  static const _columns =
      'id, source, external_id, company_name, rnc, legal_name, trade_name, '
      'email, contact_name, contact_phone, already_authorized, '
      'alanube_company_id, company_registered, requested_at, received_at, '
      'status, notes, handled_at';

  /// Las más nuevas primero.
  Future<List<ExternalEcfRequest>> list() async {
    final rows = await _client
        .from('external_ecf_requests')
        .select(_columns)
        .order('received_at', ascending: false)
        .limit(200);
    return rows
        .map(
          (e) => ExternalEcfRequest.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(growable: false);
  }

  /// Cambia el estado de seguimiento y, si se pasa, la nota.
  ///
  /// `handled_by` / `handled_at` se sellan al sacarla de "nueva": sirven para
  /// saber quién la tomó y desde cuándo lleva ahí.
  Future<void> updateStatus({
    required String id,
    required String status,
    String? notes,
  }) async {
    final patch = <String, dynamic>{
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (notes != null) 'notes': notes.trim().isEmpty ? null : notes.trim(),
    };
    if (status != 'new') {
      patch['handled_by'] = _client.auth.currentUser?.id;
      patch['handled_at'] = DateTime.now().toUtc().toIso8601String();
    } else {
      patch['handled_by'] = null;
      patch['handled_at'] = null;
    }

    await _client.from('external_ecf_requests').update(patch).eq('id', id);
  }
}

final externalEcfRequestsRepositoryProvider =
    Provider<ExternalEcfRequestsRepository>((ref) {
      return ExternalEcfRequestsRepository(ref.watch(supabaseProvider));
    });

final externalEcfRequestsProvider =
    FutureProvider<List<ExternalEcfRequest>>((ref) {
      return ref.watch(externalEcfRequestsRepositoryProvider).list();
    });

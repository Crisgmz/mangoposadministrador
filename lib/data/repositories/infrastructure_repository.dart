import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/supabase_client.dart';
import '../../domain/models/vps_instance.dart';

/// Llama a la Edge Function `hostinger-vps-status` que proxea a la API
/// de Hostinger. La API key vive como secret de Supabase, NUNCA en el
/// cliente Flutter.
class InfrastructureRepository {
  InfrastructureRepository(this._client);

  final SupabaseClient _client;

  Future<List<VpsInstance>> vpsStatus() async {
    final res = await _client.functions.invoke('hostinger-vps-status');
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Respuesta inesperada de hostinger-vps-status: $data');
    }
    if (data['error'] != null) {
      throw StateError(data['error'].toString());
    }
    final list = data['instances'];
    if (list is! List) return const [];
    return list
        .cast<Map<String, dynamic>>()
        .map(VpsInstance.fromJson)
        .toList(growable: false);
  }
}

final infrastructureRepositoryProvider =
    Provider<InfrastructureRepository>((ref) {
  return InfrastructureRepository(ref.watch(supabaseProvider));
});

/// Status de los VPS de Hostinger. Refrescable manualmente con `invalidate`.
final vpsStatusProvider = FutureProvider<List<VpsInstance>>((ref) {
  return ref.watch(infrastructureRepositoryProvider).vpsStatus();
});

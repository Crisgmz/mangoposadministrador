import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Inicializa Supabase con credenciales del `.env`.
///
/// Llamar una sola vez en `main()` antes de runApp.
Future<void> initSupabase() async {
  final url = dotenv.env['SUPABASE_URL'] ?? '';
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  if (url.isEmpty || anonKey.isEmpty) {
    throw StateError(
      'SUPABASE_URL / SUPABASE_ANON_KEY ausentes. Revisa .env (copia .env.example).',
    );
  }

  await Supabase.initialize(
    url: url,
    anonKey: anonKey,
    debug: false,
  );
}

/// Cliente Supabase global. Riverpod-friendly.
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../network/supabase_client.dart';

/// Estado de auth derivado del stream de Supabase. Se reconstruye al login,
/// logout y refresh de sesión.
final authStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseProvider);
  return client.auth.onAuthStateChange;
});

/// Sesión actual (puede ser null).
final sessionProvider = Provider<Session?>((ref) {
  final asyncState = ref.watch(authStateProvider);
  return asyncState.maybeWhen(
    data: (s) => s.session,
    orElse: () => Supabase.instance.client.auth.currentSession,
  );
});

/// `true` si hay un usuario autenticado.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(sessionProvider) != null;
});

/// Verifica contra `platform_operators` si el usuario actual está autorizado
/// como operador de plataforma. Devuelve `false` si no hay sesión.
///
/// La tabla y la función se crean en `supabase/migrations/0001_platform_operators.sql`.
final isPlatformOperatorProvider = FutureProvider<bool>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return false;

  final client = ref.watch(supabaseProvider);
  try {
    final result = await client.rpc('is_platform_operator');
    return result == true;
  } catch (_) {
    // Falla cerrada: si la RPC no existe aún o devuelve error, asumimos no operador.
    return false;
  }
});

/// `true` si el usuario debe cambiar su contraseña antes de operar la consola.
///
/// La RPC `must_change_password` y la columna del mismo nombre en
/// `platform_operators` se crean en
/// `supabase/migrations/0002_super_owner_and_password_change.sql`.
final mustChangePasswordProvider = FutureProvider<bool>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return false;

  final client = ref.watch(supabaseProvider);
  try {
    final result = await client.rpc('must_change_password');
    return result == true;
  } catch (_) {
    // Falla cerrada: si la RPC no existe aún, no forzamos cambio.
    return false;
  }
});

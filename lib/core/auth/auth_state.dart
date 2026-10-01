import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// Email de la sesión actual — para poder decirle al usuario CON QUÉ cuenta
/// entró cuando el acceso se le niega.
final currentUserEmailProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider)?.user.email;
});

/// No se pudo VERIFICAR el acceso (red caída, RPC con error, token que no
/// refrescó). No es lo mismo que "esta cuenta no es operador": esto se
/// reintenta, aquello no.
class OperatorCheckException implements Exception {
  const OperatorCheckException(this.cause);
  final Object cause;

  @override
  String toString() => 'OperatorCheckException: $cause';
}

/// Verifica contra `platform_operators` si el usuario actual está autorizado
/// como operador de plataforma.
///
/// TRES resultados, no dos — y esa es la corrección importante:
///   * `true`  → está en la whitelist.
///   * `false` → NO está en la whitelist (la RPC respondió que no).
///   * error   → no se pudo verificar; la pantalla ofrece reintentar.
///
/// Antes cualquier excepción se convertía en `false` ("falla cerrada"), así
/// que un token vencido, un corte de red o un 500 pasajero le decían al
/// operador legítimo "esta cuenta no está autorizada" — un mensaje definitivo
/// para un problema temporal, y sin más salida que cerrar sesión.
final isPlatformOperatorProvider = FutureProvider<bool>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return false;

  final client = ref.watch(supabaseProvider);

  // Un JWT vencido devuelve 401 y antes eso se leía como "no autorizado".
  // Caso real: dejar la consola abierta y volver al día siguiente. Se fuerza
  // el refresh ANTES de preguntar por la whitelist.
  if (session.isExpired) {
    try {
      await client.auth.refreshSession();
    } catch (e) {
      throw OperatorCheckException(e);
    }
  }

  Object? lastError;
  // Tres intentos con backoff corto: la RPC es barata y el fallo típico
  // (red intermitente al abrir la app) se resuelve en el segundo intento.
  for (var attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
    }
    try {
      final result = await client.rpc('is_platform_operator');
      // Respuesta explícita del servidor: esto SÍ es una decisión de acceso.
      return result == true;
    } catch (e) {
      lastError = e;
      debugPrint('[auth] is_platform_operator falló (intento ${attempt + 1}): $e');
    }
  }
  throw OperatorCheckException(lastError ?? 'desconocido');
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
    // Acá sí falla ABIERTA a propósito: si no se puede leer el flag, dejar
    // entrar es preferible a bloquear la consola por un chequeo secundario.
    // Se vuelve a evaluar en el próximo refresh de sesión.
    return false;
  }
});

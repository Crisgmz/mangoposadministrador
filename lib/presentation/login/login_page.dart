import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/auth_state.dart';
import '../../core/network/supabase_client.dart';

/// Pantalla de login email/password contra Supabase Auth.
///
/// El gate `platformOperatorGuard` se encarga de bloquear a usuarios
/// autenticados que NO estén en `platform_operators`.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailCtl = TextEditingController();
  final _pwdCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtl.dispose();
    _pwdCtl.dispose();
    super.dispose();
  }

  /// Espera a que el autofill del navegador llegue a los controllers.
  ///
  /// En Flutter Web, Chrome rellena email/password en el input oculto y los
  /// valores viajan al framework por el canal de plataforma — es asíncrono.
  /// `finishAutofillContext()` lo dispara, pero el `await Duration.zero` que
  /// había antes no alcanzaba: el primer clic validaba con los controllers
  /// todavía vacíos, no pasaba nada visible, y recién el SEGUNDO clic
  /// funcionaba. De ahí el "tengo que darle dos veces".
  ///
  /// Se sondea en pasos cortos y se sale apenas hay datos, así que quien
  /// escribió a mano no espera nada.
  Future<void> _waitForAutofill() async {
    bool filled() =>
        _emailCtl.text.trim().isNotEmpty && _pwdCtl.text.isNotEmpty;
    if (filled()) return;
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!mounted || filled()) return;
    }
  }

  Future<void> _submit() async {
    if (_loading) return; // doble clic rápido: un solo intento
    TextInput.finishAutofillContext();
    await _waitForAutofill();
    if (!mounted) return;

    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(supabaseProvider);
      await client.auth.signInWithPassword(
        email: _emailCtl.text.trim(),
        password: _pwdCtl.text,
      );
      // El redirect lo maneja platformOperatorGuard al cambiar el authState.
    } on Exception catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('invalid login')) return 'Email o contraseña incorrectos.';
    if (msg.contains('email not confirmed')) return 'Debes confirmar tu email primero.';
    if (msg.contains('network') || msg.contains('socket')) {
      return 'Sin conexión. Verifica tu internet.';
    }
    return 'No se pudo iniciar sesión. Intenta de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SizedBox(
                        width: 96,
                        height: 96,
                        child: Image.asset(
                          'assets/images/logo_administrador.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'MangoPOS Admin',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Operator Console',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.mutedForeground,
                        fontSize: 11,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _emailCtl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email corporativo',
                        prefixIcon: Icon(HugeIcons.strokeRoundedMail01, size: 18),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requerido';
                        if (!v.contains('@')) return 'Email inválido';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _pwdCtl,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(HugeIcons.strokeRoundedLockPassword, size: 18),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? HugeIcons.strokeRoundedView : HugeIcons.strokeRoundedViewOff,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Requerido';
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.destructive.withValues(alpha: 0.08),
                          border: Border.all(color: AppColors.destructive.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(HugeIcons.strokeRoundedAlertCircle, color: AppColors.destructive, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: AppColors.destructive, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Entrar'),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        'Solo para operadores autorizados de MangoPOS.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.mutedForeground.withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Layout compartido por las dos pantallas de bloqueo. Mismo esqueleto,
/// distinto mensaje y distintas salidas.
class _GateScreen extends StatelessWidget {
  const _GateScreen({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actions,
    this.footnote,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final List<Widget> actions;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: iconColor, size: 30),
                ),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.mutedForeground),
                ),
                if (footnote != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    footnote!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: actions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla mostrada cuando el servidor respondió que el usuario NO está en
/// `platform_operators`. Es una respuesta definitiva, pero igual ofrece
/// reintentar: si acaban de agregar la cuenta a la whitelist, el operador no
/// debería tener que cerrar sesión y volver a entrar para que se note.
class ForbiddenPage extends ConsumerWidget {
  const ForbiddenPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(currentUserEmailProvider);
    return _GateScreen(
      icon: HugeIcons.strokeRoundedShieldBlockchain,
      iconColor: AppColors.destructive,
      title: 'Acceso restringido',
      message:
          'Esta cuenta no está autorizada como operador de plataforma. '
          'Si crees que es un error, contacta al equipo de Mango.',
      // Decir CON QUÉ cuenta entró evita el caso más común de este mensaje:
      // haber iniciado sesión con el correo personal en vez del de operador.
      footnote: email,
      actions: [
        OutlinedButton(
          onPressed: () => ref.invalidate(isPlatformOperatorProvider),
          child: const Text('Reintentar'),
        ),
        FilledButton(
          onPressed: () async {
            await ref.read(supabaseProvider).auth.signOut();
          },
          child: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}

/// Pantalla mostrada cuando NO SE PUDO verificar el acceso: red caída, RPC
/// con error, token que no refrescó.
///
/// Existe porque antes este caso caía en "Acceso restringido" — un mensaje
/// definitivo, que culpa a la cuenta, para un problema temporal, y cuya única
/// salida era cerrar sesión y volver a chocar con lo mismo.
class AccessCheckErrorPage extends ConsumerWidget {
  const AccessCheckErrorPage({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _GateScreen(
      icon: HugeIcons.strokeRoundedWifiDisconnected01,
      iconColor: AppColors.warning,
      title: 'No pudimos verificar tu acceso',
      message:
          'No se pudo confirmar tus permisos de operador. Suele ser un '
          'problema de conexión — no es que tu cuenta esté bloqueada.',
      footnote: error == null ? null : _shortError(error!),
      actions: [
        FilledButton(
          onPressed: () => ref.invalidate(isPlatformOperatorProvider),
          child: const Text('Reintentar'),
        ),
        OutlinedButton(
          onPressed: () async {
            await ref.read(supabaseProvider).auth.signOut();
          },
          child: const Text('Cerrar sesión'),
        ),
      ],
    );
  }

  /// Una línea de diagnóstico, no el stack entero: quien lee esto está
  /// atascado y solo necesita algo que copiar al reportarlo.
  static String _shortError(Object error) {
    final text = error is OperatorCheckException
        ? error.cause.toString()
        : error.toString();
    final firstLine = text.split('\n').first.trim();
    return firstLine.length > 140
        ? '${firstLine.substring(0, 140)}…'
        : firstLine;
  }
}

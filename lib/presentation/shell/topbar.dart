import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/breakpoints.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../domain/models/platform_alert.dart';
import 'env_selector.dart';

/// Foco del buscador global. Vive en un provider para que el atajo ⌘K /
/// Ctrl+K —registrado en el shell, fuera del topbar— pueda enfocarlo.
final topbarSearchFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'topbar-search');
  ref.onDispose(node.dispose);
  return node;
});

/// Barra superior pegajosa. En desktop muestra reloj AST, búsqueda y acciones.
/// En móvil colapsa la búsqueda dejando reloj compacto + acciones.
class Topbar extends ConsumerStatefulWidget {
  const Topbar({super.key, this.onMenuTap});

  final VoidCallback? onMenuTap;

  @override
  ConsumerState<Topbar> createState() => _TopbarState();
}

class _TopbarState extends ConsumerState<Topbar> {
  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.isDesktop(context);

    // La campana cuenta lo que EXIGE atención ahora: las críticas. Si solo
    // hay advertencias, el número igual se muestra pero en naranja de marca
    // —hay trabajo— y no en rojo, que significa "algo está caído".
    final alerts = ref.watch(filteredAlertsProvider).valueOrNull;
    final criticals =
        alerts?.where((a) => a.severity == AlertSeverity.critical).length ?? 0;
    final alertsCount = criticals > 0 ? criticals : (alerts?.length ?? 0);
    final alertsColor = criticals > 0
        ? AppColors.destructive
        : AppColors.accent;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.85),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16),
      child: Row(
        children: [
          if (!isDesktop && widget.onMenuTap != null) ...[
            IconButton(
              tooltip: 'Menú',
              icon: const Icon(HugeIcons.strokeRoundedMenu01),
              onPressed: widget.onMenuTap,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Row(
              children: [
                if (isDesktop) ...[
                  // Anima a 60 fps sin parar. En su propia capa: sin esto
                  // repintaba el topbar entero en cada frame, en todas las
                  // pantallas, y competía con las transiciones.
                  const RepaintBoundary(child: _LiveDot()),
                  const SizedBox(width: 8),
                  const Text(
                    'EN VIVO',
                    style: TextStyle(
                      color: AppColors.mutedForeground,
                      fontSize: 10.5,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 20, color: AppColors.border),
                  const SizedBox(width: 12),
                ],
                Flexible(child: _TopbarDate(compact: !isDesktop)),
              ],
            ),
          ),
          if (isDesktop) ...[const _SearchField(), const SizedBox(width: 8)],
          EnvSelector(compact: !isDesktop),
          const SizedBox(width: 6),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: criticals > 0
                    ? '$criticals alertas críticas'
                    : 'Alertas',
                icon: const Icon(HugeIcons.strokeRoundedNotification03),
                onPressed: () => context.go('/alertas'),
              ),
              if (alertsCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    decoration: BoxDecoration(
                      color: alertsColor,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      alertsCount > 99 ? '99+' : '$alertsCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fecha y hora del topbar.
///
/// Tiene su propio timer: antes el `setState` del segundero vivía en el
/// `Topbar` entero, así que buscador, selector de entorno y campana se
/// reconstruían una vez por segundo en TODAS las pantallas. Y como la
/// etiqueta solo llega al minuto, el tick es de 20 s.
class _TopbarDate extends StatefulWidget {
  const _TopbarDate({required this.compact});

  final bool compact;

  @override
  State<_TopbarDate> createState() => _TopbarDateState();
}

class _TopbarDateState extends State<_TopbarDate> {
  late Timer _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Locale es-DO con zona AST (UTC-4) — sin tz package, asumimos hora
    // local del navegador.
    final fmt = widget.compact
        ? DateFormat('EEE d MMM · HH:mm', 'es')
        : DateFormat("EEEE, d MMMM 'a las' HH:mm", 'es');
    return Text(
      fmt.format(_now),
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppColors.mutedForeground,
        fontSize: 13,
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, _) {
        final t = (_ctl.value < 0.5 ? _ctl.value * 2 : (1 - _ctl.value) * 2);
        return SizedBox(
          width: 12,
          height: 12,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 8 + 8 * t,
                height: 8 + 8 * t,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.4 * (1 - t)),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Buscador global. Escribe en `businessSearchQueryProvider` —el mismo estado
/// que filtra la tabla de negocios— y al enviar salta al listado completo.
/// Antes era un campo decorativo: se tecleaba y no pasaba nada.
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    ref.read(businessSearchQueryProvider.notifier).state = value.trim();
    if (value.trim().isEmpty) return;
    context.go('/negocios');
  }

  @override
  Widget build(BuildContext context) {
    final focus = ref.watch(topbarSearchFocusProvider);
    final hasText = _controller.text.isNotEmpty;

    return SizedBox(
      width: 300,
      height: 36,
      child: TextField(
        controller: _controller,
        focusNode: focus,
        onChanged: (_) => setState(() {}),
        onSubmitted: _submit,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Buscar negocio, RNC o dominio…',
          hintStyle: const TextStyle(
            fontSize: 13,
            color: AppColors.mutedForeground,
          ),
          prefixIcon: const Icon(HugeIcons.strokeRoundedSearch01, size: 16),
          suffixIcon: hasText
              ? IconButton(
                  tooltip: 'Limpiar',
                  iconSize: 15,
                  splashRadius: 14,
                  icon: const Icon(HugeIcons.strokeRoundedCancel01),
                  onPressed: () {
                    _controller.clear();
                    _submit('');
                    setState(() {});
                  },
                )
              : const _ShortcutHint(),
          suffixIconConstraints: const BoxConstraints(minWidth: 46),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          isDense: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

/// Pista del atajo. Se muestra solo si el atajo existe de verdad — en web y
/// escritorio lo registra `AppShell`.
class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint();

  @override
  Widget build(BuildContext context) {
    final isApple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Align(
        alignment: Alignment.centerRight,
        widthFactor: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.muted,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            isApple ? '⌘K' : 'Ctrl K',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: AppColors.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

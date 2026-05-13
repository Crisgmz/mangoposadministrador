import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/breakpoints.dart';
import 'env_selector.dart';

/// Barra superior pegajosa. En desktop muestra reloj AST, búsqueda y acciones.
/// En móvil colapsa la búsqueda dejando reloj compacto + acciones.
class Topbar extends StatefulWidget {
  const Topbar({super.key, this.alertsCount = 0, this.onMenuTap});

  final int alertsCount;
  final VoidCallback? onMenuTap;

  @override
  State<Topbar> createState() => _TopbarState();
}

class _TopbarState extends State<Topbar> {
  late Timer _ticker;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  String _formatNow({required bool compact}) {
    // Locale es-DO con zona AST (UTC-4) — sin tz package, asumimos hora local del navegador.
    final fmt = compact
        ? DateFormat('EEE d MMM · HH:mm', 'es')
        : DateFormat("EEEE, d MMMM 'a las' HH:mm", 'es');
    return fmt.format(_now);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.isDesktop(context);

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
                  _LiveDot(),
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
                Flexible(
                  child: Text(
                    _formatNow(compact: !isDesktop),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.mutedForeground,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isDesktop) ...[
            _SearchField(),
            const SizedBox(width: 8),
          ],
          EnvSelector(compact: !isDesktop),
          const SizedBox(width: 6),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Alertas',
                icon: const Icon(HugeIcons.strokeRoundedNotification03),
                onPressed: () {},
              ),
              if (widget.alertsCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${widget.alertsCount}',
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
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(HugeIcons.strokeRoundedRefresh),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
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

class _SearchField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 36,
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Buscar negocio...',
          prefixIcon: const Icon(HugeIcons.strokeRoundedSearch01, size: 16),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          isDense: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

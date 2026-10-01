import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_prefetch.dart';
import '../../app/theme/app_colors.dart';
import '../../app/widgets/nav_badges.dart';
import '../../app/widgets/nav_items.dart';

/// Sidebar fijo de desktop (≥1024px): fondo verde bosque, marca arriba,
/// navegación agrupada al medio, footer del operador abajo.
///
/// La navegación va por bloques (Operación / Salud / Comercial / Sistema)
/// porque catorce destinos planos obligaban a recorrer la lista entera para
/// encontrar uno. Con encabezados, el ojo salta al bloque y después al item.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 256,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBackground,
        border: Border(right: BorderSide(color: AppColors.sidebarBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Brand(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
              children: [
                for (final section in NavSection.values) ...[
                  _SectionHeading(label: section.label),
                  for (final item in navItemsOf(section))
                    _SidebarItem(item: item, active: _isActive(item.path)),
                ],
              ],
            ),
          ),
          const _OperatorFooter(),
        ],
      ),
    );
  }

  bool _isActive(String path) {
    if (path == '/') return currentPath == '/';
    return currentPath == path || currentPath.startsWith('$path/');
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: AppColors.sidebarForeground.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.sidebarBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(4),
            child: Image.asset(
              'assets/images/logo_administrador.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MangoPOS',
                style: TextStyle(
                  color: AppColors.sidebarAccentForeground,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  height: 1.1,
                ),
              ),
              Text(
                'Administrador',
                style: TextStyle(
                  color: AppColors.sidebarAccentForeground,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends ConsumerStatefulWidget {
  const _SidebarItem({required this.item, required this.active});

  final NavItem item;
  final bool active;

  @override
  ConsumerState<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends ConsumerState<_SidebarItem> {
  bool _hovering = false;
  Timer? _prefetchTimer;

  @override
  void dispose() {
    _prefetchTimer?.cancel();
    super.dispose();
  }

  void _onEnter() {
    setState(() => _hovering = true);
    // Se espera a que el mouse se APOYE: cruzar el menú de arriba abajo no
    // tiene que disparar la carga de cada sección por la que pasa.
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 120), _prefetch);
  }

  void _onExit() {
    _prefetchTimer?.cancel();
    setState(() => _hovering = false);
  }

  void _prefetch() {
    _prefetchTimer?.cancel();
    if (!widget.active) prefetchRoute(ref, widget.item.path);
  }

  @override
  Widget build(BuildContext context) {
    // Sobre el verde bosque, el item activo usa un overlay blanco translúcido
    // (patrón "on-primary" de Material) más una barra de acento a la
    // izquierda: el color solo no alcanza a marcar posición en una lista
    // agrupada tan larga.
    final activeBg = Colors.white.withValues(alpha: 0.20);
    final hoverBg = Colors.white.withValues(alpha: 0.08);
    final fg = widget.active
        ? Colors.white
        : Colors.white.withValues(alpha: 0.80);

    final badgeCount = widget.item.badge == NavBadge.none
        ? null
        : ref.watch(navBadgeCountProvider(widget.item.badge));

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _onEnter(),
        onExit: (_) => _onExit(),
        child: GestureDetector(
          // Al apretar, no al soltar: son ~100 ms más de ventaja, y en táctil
          // (menú lateral del celular) es la única señal previa que hay.
          onTapDown: (_) => _prefetch(),
          onTap: () => context.go(widget.item.path),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: widget.active
                  ? activeBg
                  : (_hovering ? hoverBg : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(
                  width: 2,
                  color: widget.active ? AppColors.accent : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(widget.item.icon, color: fg, size: 17),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (badgeCount != null && badgeCount > 0)
                  _NavBadge(
                    count: badgeCount,
                    color: navBadgeColor(widget.item.badge),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

class _OperatorFooter extends StatelessWidget {
  const _OperatorFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.sidebarBorder)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'OP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Operador',
                        style: TextStyle(
                          color: AppColors.sidebarForeground.withValues(
                            alpha: 0.6,
                          ),
                          fontSize: 10.5,
                          height: 1.2,
                        ),
                      ),
                      const Text(
                        'Plataforma MangoPOS',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.sidebarAccentForeground,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              'v1.0.0 · build 240507',
              style: TextStyle(
                color: AppColors.sidebarForeground.withValues(alpha: 0.5),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

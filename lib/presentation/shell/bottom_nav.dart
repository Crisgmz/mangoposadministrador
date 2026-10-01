import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_prefetch.dart';
import '../../app/theme/app_colors.dart';
import '../../app/widgets/nav_badges.dart';
import '../../app/widgets/nav_items.dart';

/// Barra de navegación inferior para móvil/tablet (<1024px). Replica
/// `BottomNav.tsx` del prototipo. Solo muestra items con `showInBottomNav`.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final items = kNavItems.where((i) => i.showInBottomNav).toList();
    final currentIndex = items.indexWhere((i) => _isActive(i.path));

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.sidebarBackground,
        border: Border(top: BorderSide(color: AppColors.sidebarBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _BottomItem(
                    item: items[i],
                    active: i == currentIndex,
                    onTap: () => context.go(items[i].path),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isActive(String path) {
    if (path == '/') return currentPath == '/';
    return currentPath == path || currentPath.startsWith('$path/');
  }
}

class _BottomItem extends ConsumerWidget {
  const _BottomItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sobre el verde bosque del fondo, el blanco (con y sin alpha) separa
    // activo de inactivo mejor que un cambio de matiz, y deja el naranja
    // libre para lo único que debe gritar acá: los contadores.
    final color = active ? Colors.white : Colors.white.withValues(alpha: 0.65);

    // El mismo contador que muestra el sidebar. En móvil pesa más: es la
    // única señal de que hay trabajo esperando en una pantalla que no se ve.
    final badgeCount = item.badge == NavBadge.none
        ? null
        : ref.watch(navBadgeCountProvider(item.badge));

    return InkWell(
      // Al apoyar el dedo ya se piden los datos de la sección: en táctil no
      // hay hover, y son ~100 ms de ventaja sobre esperar a que suelte.
      onTapDown: active ? null : (_) => prefetchRoute(ref, item.path),
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: 21,
                color: color,
                shadows: active
                    ? [
                        Shadow(
                          color: Colors.white.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                item.shortLabel,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (badgeCount != null && badgeCount > 0)
            Positioned(
              top: 6,
              right: 14,
              child: Container(
                constraints: const BoxConstraints(minWidth: 15),
                height: 15,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: navBadgeColor(item.badge),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

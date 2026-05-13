import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
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

class _BottomItem extends StatelessWidget {
  const _BottomItem({required this.item, required this.active, required this.onTap});

  final NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppColors.accent
        : AppColors.sidebarForeground.withValues(alpha: 0.7);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            item.icon,
            size: 22,
            color: color,
            shadows: active
                ? [Shadow(color: AppColors.accent.withValues(alpha: 0.6), blurRadius: 8)]
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
    );
  }
}

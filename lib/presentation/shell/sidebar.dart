import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/widgets/nav_items.dart';
import '../../data/repositories/pending_accounts_repository.dart';

/// Sidebar fijo de desktop (≥1024px). Replica `Sidebar.tsx` del prototipo:
/// fondo verde oscuro, marca arriba, navegación al medio, footer del operador.
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
          _Brand(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              children: [
                for (final item in kNavItems)
                  _SidebarItem(
                    item: item,
                    active: _isActive(item.path),
                  ),
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

class _Brand extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final activeBg = AppColors.sidebarAccent;
    final hoverBg = AppColors.sidebarAccent.withValues(alpha: 0.5);
    final fg = widget.active
        ? AppColors.sidebarAccentForeground
        : AppColors.sidebarForeground.withValues(alpha: 0.75);

    // Badge contador solo para el item de cuentas pendientes. Si en el
    // futuro otros items necesitan badge, agregar un `badgeProvider` opcional
    // al NavItem y mapear acá.
    int? badge;
    if (widget.item.path == '/pendientes') {
      badge = ref.watch(pendingAccountsCountProvider).valueOrNull;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: () => context.go(widget.item.path),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                Icon(widget.item.icon, color: fg, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null && badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
          color: AppColors.sidebarAccent.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Operador',
              style: TextStyle(
                color: AppColors.sidebarForeground.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Plataforma MangoPOS',
              style: TextStyle(
                color: AppColors.sidebarAccentForeground,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
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

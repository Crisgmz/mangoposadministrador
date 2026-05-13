import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../core/state/environment_filter.dart';
import '../../domain/models/business_environment.dart';

/// Pill compacto en el topbar que muestra el entorno seleccionado y
/// permite alternar entre producción / sandbox / todos.
///
/// Persistencia: el estado vive en `environmentFilterProvider` (Riverpod),
/// que es global mientras el proceso está vivo.
class EnvSelector extends ConsumerWidget {
  const EnvSelector({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(environmentFilterProvider);
    final (bg, fg, dot) = _colorsFor(selected);
    final label = selected == null
        ? 'Todos'
        : (compact ? selected.shortLabel : selected.label);

    return PopupMenuButton<BusinessEnvironment?>(
      tooltip: 'Filtrar por entorno',
      position: PopupMenuPosition.under,
      onSelected: (value) =>
          ref.read(environmentFilterProvider.notifier).state = value,
      itemBuilder: (_) => [
        _menuItem(
          value: BusinessEnvironment.production,
          label: 'Producción',
          dot: AppColors.success,
          selected: selected == BusinessEnvironment.production,
        ),
        _menuItem(
          value: BusinessEnvironment.sandbox,
          label: 'Sandbox',
          dot: AppColors.accent,
          selected: selected == BusinessEnvironment.sandbox,
        ),
        const PopupMenuDivider(),
        _menuItem(
          value: null,
          label: 'Todos los entornos',
          dot: AppColors.mutedForeground,
          selected: selected == null,
        ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: fg.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              HugeIcons.strokeRoundedArrowDown01,
              size: 14,
              color: fg.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<BusinessEnvironment?> _menuItem({
    required BusinessEnvironment? value,
    required String label,
    required Color dot,
    required bool selected,
  }) {
    return PopupMenuItem<BusinessEnvironment?>(
      value: value,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(
              HugeIcons.strokeRoundedTick02,
              size: 14,
              color: AppColors.primary,
            ),
          ],
        ],
      ),
    );
  }

  (Color bg, Color fg, Color dot) _colorsFor(BusinessEnvironment? env) {
    if (env == BusinessEnvironment.production) {
      return (
        AppColors.success.withValues(alpha: 0.10),
        AppColors.success,
        AppColors.success,
      );
    }
    if (env == BusinessEnvironment.sandbox) {
      return (
        AppColors.accent.withValues(alpha: 0.10),
        AppColors.accent,
        AppColors.accent,
      );
    }
    return (
      AppColors.muted,
      AppColors.foreground,
      AppColors.mutedForeground,
    );
  }
}

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Toggle estilo "pill" del prototipo: opciones en línea sobre un fondo
/// muted; la opción activa lleva fondo oscuro + texto blanco.
///
/// Genérico sobre `T` para que cada caller defina su propio enum/tipo.
class PillToggle<T> extends StatelessWidget {
  const PillToggle({
    required this.options,
    required this.value,
    required this.onChanged,
    this.activeColor,
    super.key,
  });

  /// Pares (valor, label) en orden de aparición.
  final List<({T value, String label})> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Color de fondo de la pill activa. Default: `foreground` (oscuro forest).
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final active = activeColor ?? AppColors.foreground;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.muted,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final opt in options)
            _PillItem(
              label: opt.label,
              selected: opt.value == value,
              activeColor: active,
              onTap: () => onChanged(opt.value),
            ),
        ],
      ),
    );
  }
}

class _PillItem extends StatelessWidget {
  const _PillItem({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: selected ? Colors.white : AppColors.mutedForeground,
          ),
        ),
      ),
    );
  }
}

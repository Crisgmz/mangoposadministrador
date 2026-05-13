import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Placeholder común para módulos aún no implementados (Fase 0).
/// Muestra el título de la pantalla y una nota de "próximamente".
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.subtitle,
    this.phase,
  });

  final String title;
  final String subtitle;
  final String? phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedForeground),
        ),
        const SizedBox(height: 32),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.construction_rounded, color: AppColors.accent, size: 28),
              ),
              const SizedBox(height: 16),
              Text('Pantalla en construcción', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                phase != null ? 'Llega en $phase del roadmap.' : 'Próximamente.',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Header compartido por todas las pantallas internas: kicker naranja en mayúsculas,
/// título grande y subtítulo opcional.
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.kicker,
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String kicker;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          kicker.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.mutedForeground,
            ),
          ),
        ],
      ],
    );

    if (trailing == null) return left;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 700;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              left,
              const SizedBox(height: 14),
              trailing!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [Expanded(child: left), trailing!],
        );
      },
    );
  }
}

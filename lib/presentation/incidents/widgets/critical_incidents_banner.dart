import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../data/repositories/incidents_repository.dart';

/// Banner rojo compacto que aparece en el dashboard cuando hay incidentes
/// críticos abiertos. Click → `/incidentes`.
class CriticalIncidentsBanner extends ConsumerWidget {
  const CriticalIncidentsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final criticals = ref.watch(criticalOpenIncidentsProvider);
    final list = criticals.valueOrNull ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();

    final first = list.first;
    final extra = list.length - 1;
    return InkWell(
      onTap: () => context.go('/incidentes'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.destructive.withValues(alpha: 0.08),
          border: Border.all(
              color: AppColors.destructive.withValues(alpha: 0.30),
              width: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.destructive.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                HugeIcons.strokeRoundedAlertCircle,
                color: AppColors.destructive,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        'INCIDENTES CRÍTICOS',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: AppColors.destructive,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.destructive,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${list.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    first.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                  if (first.description != null && first.description!.isNotEmpty)
                    Text(
                      first.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  if (extra > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+ $extra más · toca para ver todos',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.destructive,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              HugeIcons.strokeRoundedArrowRight01,
              size: 16,
              color: AppColors.destructive,
            ),
          ],
        ),
      ),
    );
  }
}

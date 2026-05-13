import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/format/formatters.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../domain/models/platform_alert.dart';
import '../../shared/business_avatar.dart';

class AlertsPanel extends ConsumerWidget {
  const AlertsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(filteredAlertsProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(count: alertsAsync.value?.length),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          Expanded(
            child: alertsAsync.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Error cargando alertas',
                    style: TextStyle(
                      color: AppColors.destructive,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              data: (alerts) => alerts.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      itemCount: alerts.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.border,
                      ),
                      itemBuilder: (_, i) => _AlertRow(alert: alerts[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.count});
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        children: [
          const Icon(
            HugeIcons.strokeRoundedAlert02,
            color: AppColors.accent,
            size: 18,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Alertas activas',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
          ),
          if (count != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No hay alertas activas 🎉',
          style: TextStyle(color: AppColors.mutedForeground, fontSize: 13),
        ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});
  final PlatformAlert alert;

  IconData get _icon {
    switch (alert.type) {
      case AlertType.agentOffline:
        return HugeIcons.strokeRoundedWifiDisconnected01;
      case AlertType.ncfCritical:
        return HugeIcons.strokeRoundedInvoice03;
      case AlertType.planExpiring:
        return HugeIcons.strokeRoundedCreditCard;
      case AlertType.unknown:
        return HugeIcons.strokeRoundedAlert02;
    }
  }

  @override
  Widget build(BuildContext context) {
    final critical = alert.severity == AlertSeverity.critical;
    final iconBg = critical
        ? AppColors.destructive.withValues(alpha: 0.10)
        : AppColors.warning.withValues(alpha: 0.15);
    final iconFg = critical ? AppColors.destructive : AppColors.warning;

    final extra = alert.type == AlertType.agentOffline
        ? formatRelative(alert.referenceAt)
        : null;

    return InkWell(
      onTap: () => context.go('/negocios/${alert.businessId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar del negocio + badge de severidad superpuesto en la
            // esquina inferior-derecha (icono pequeño con el tipo de alerta).
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  BusinessAvatar(
                    businessId: alert.businessId,
                    businessName: alert.businessName,
                    size: 40,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: iconBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Icon(_icon, size: 11, color: iconFg),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.businessName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  if (alert.detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        extra != null
                            ? '${alert.detail} · $extra'
                            : alert.detail,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.mutedForeground.withValues(alpha: 0.85),
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
              color: AppColors.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

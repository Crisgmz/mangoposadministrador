import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/format/formatters.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../data/repositories/pending_accounts_repository.dart';
import '../../../domain/models/business_overview.dart';
import '../../pending/pending_actions.dart';
import '../../shared/business_avatar.dart';

/// Negocios cuya membresía vence dentro de 7 días (o ya venció), del más
/// urgente al menos urgente.
///
/// Una membresía vencida sigue siendo cobrable, así que entra en la lista en
/// vez de desaparecer: es justo la que hay que perseguir.
final expiringMembershipsProvider = Provider<List<BusinessOverview>>((ref) {
  final rows = ref.watch(filteredOverviewProvider).valueOrNull ?? const [];
  final out = rows.where((b) {
    if (!b.isActive || b.planEndDate == null) return false;
    return daysUntil(b.planEndDate) <= 7;
  }).toList();
  out.sort((a, b) => a.planEndDate!.compareTo(b.planEndDate!));
  return List<BusinessOverview>.unmodifiable(out);
});

/// Card lateral: cuentas nuevas esperando aprobación.
class PendingAccountsCard extends ConsumerWidget {
  const PendingAccountsCard({super.key, this.maxRows = 3});

  final int maxRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(pendingAccountsListProvider).valueOrNull ?? const [];
    final rows = all.take(maxRows).toList(growable: false);

    return _SidePanel(
      icon: HugeIcons.strokeRoundedClock04,
      iconColor: AppColors.accent,
      title: 'Cuentas pendientes',
      count: all.length,
      countColor: AppColors.accent,
      emptyMessage: 'Ninguna cuenta esperando aprobación.',
      onSeeAll: all.length > rows.length
          ? () => context.go('/pendientes')
          : null,
      seeAllLabel: 'Ver las ${all.length}',
      rows: [
        for (final p in rows)
          _SideRow(
            businessId: p.businessId,
            businessName: p.businessName,
            meta: [
              formatRelative(p.createdAt),
              p.hasVerifiedCard ? 'tarjeta verificada' : 'falta tarjeta',
            ].join(' · '),
            // Sin tarjeta verificada no se aprueba a ciegas: el botón lo dice.
            actionLabel: p.hasVerifiedCard ? 'Aprobar' : 'Revisar',
            filled: p.hasVerifiedCard,
            onAction: () => openPendingDetail(context, ref, p),
          ),
      ],
    );
  }
}

/// Card lateral: membresías por vencer.
class ExpiringMembershipsCard extends ConsumerWidget {
  const ExpiringMembershipsCard({super.key, this.maxRows = 3});

  final int maxRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(expiringMembershipsProvider);
    final rows = all.take(maxRows).toList(growable: false);

    return _SidePanel(
      icon: HugeIcons.strokeRoundedCreditCard,
      iconColor: AppColors.warning,
      title: 'Membresías por vencer',
      count: all.length,
      countColor: AppColors.warning,
      emptyMessage: 'Ninguna membresía vence esta semana.',
      onSeeAll: all.length > rows.length
          ? () => context.go('/facturacion')
          : null,
      seeAllLabel: 'Ver las ${all.length}',
      rows: [
        for (final b in rows)
          _SideRow(
            businessId: b.id,
            businessName: b.name,
            // Plan, no monto: el precio de catálogo sería falso para los
            // clientes con precio especial, y la vista global no tiene el
            // efectivo. El monto real está en Facturación.
            meta: '${_dueLabel(b.planEndDate)} · ${b.plan.label}',
            actionLabel: 'Cobrar',
            filled: false,
            onAction: () => context.go('/facturacion'),
          ),
      ],
    );
  }

  static String _dueLabel(DateTime? end) {
    final days = daysUntil(end);
    if (days < 0) return 'vencida hace ${-days} d';
    if (days == 0) return 'vence hoy';
    if (days == 1) return 'vence mañana';
    return 'vence en $days d';
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.count,
    required this.countColor,
    required this.rows,
    required this.emptyMessage,
    this.onSeeAll,
    this.seeAllLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final int count;
  final Color countColor;
  final List<Widget> rows;
  final String emptyMessage;
  final VoidCallback? onSeeAll;
  final String? seeAllLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: countColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: countColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              child: Text(
                emptyMessage,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i < rows.length - 1)
                const Divider(height: 1, thickness: 1, color: AppColors.border),
            ],
          if (onSeeAll != null) ...[
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            InkWell(
              onTap: onSeeAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text(
                    seeAllLabel ?? 'Ver todas',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.businessId,
    required this.businessName,
    required this.meta,
    required this.actionLabel,
    required this.filled,
    required this.onAction,
  });

  final String businessId;
  final String businessName;
  final String meta;
  final String actionLabel;
  final bool filled;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAction,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            BusinessAvatar(
              businessId: businessId,
              businessName: businessName,
              size: 30,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    businessName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                backgroundColor: filled ? AppColors.primary : AppColors.card,
                foregroundColor: filled ? Colors.white : AppColors.foreground,
                side: filled ? null : const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

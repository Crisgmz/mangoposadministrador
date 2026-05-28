import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/pending_accounts_repository.dart';
import '../dashboard/widgets/business_table.dart';
import '../shared/page_header.dart';
import 'new_business_dialog.dart';

class BusinessesPage extends ConsumerWidget {
  const BusinessesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Negocios',
          title: 'Listado completo',
          subtitle: 'Todos los negocios registrados en la plataforma.',
          trailing: FilledButton.icon(
            onPressed: () => _onCreate(context, ref),
            icon: const Icon(HugeIcons.strokeRoundedAdd01, size: 16),
            label: const Text('Nuevo negocio'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const _StatusFilterBar(),
        const SizedBox(height: 14),
        const BusinessTable(),
      ],
    );
  }

  Future<void> _onCreate(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<NewBusinessResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NewBusinessDialog(),
    );
    if (result == null || !context.mounted) return;
    try {
      final id = await ref.read(dashboardRepositoryProvider).createBusiness(
            ownerEmail: result.ownerEmail,
            businessName: result.businessName,
            businessType: result.businessType,
            domain: result.domain,
            environment: result.environment,
            planType: result.planType,
            trialDays: result.trialDays,
          );
      ref.invalidate(platformOverviewProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.businessName} creado. Abriendo detalle…'),
        ),
      );
      context.go('/negocios/$id');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

/// Chips de filtro por status. Estado en `businessStatusFilterProvider`
/// (StateProvider global, también usado por la tabla).
class _StatusFilterBar extends ConsumerWidget {
  const _StatusFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(businessStatusFilterProvider);
    final pendingCount = ref
        .watch(pendingAccountsCountProvider)
        .valueOrNull;

    void setStatus(String? v) {
      ref.read(businessStatusFilterProvider.notifier).state = v;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Status:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.mutedForeground,
          ),
        ),
        _Chip(
          label: 'Todos',
          selected: current == null,
          color: AppColors.foreground,
          onTap: () => setStatus(null),
        ),
        _Chip(
          label: 'Activos',
          selected: current == 'active',
          color: AppColors.success,
          onTap: () => setStatus('active'),
        ),
        _Chip(
          label: 'Pending',
          selected: current == 'pending',
          color: AppColors.accent,
          badge: pendingCount == null || pendingCount == 0
              ? null
              : (pendingCount > 99 ? '99+' : '$pendingCount'),
          onTap: () => setStatus('pending'),
        ),
        _Chip(
          label: 'Inactivos',
          selected: current == 'inactive',
          color: AppColors.destructive,
          onTap: () => setStatus('inactive'),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : AppColors.muted,
          border: Border.all(
            color:
                selected ? color.withValues(alpha: 0.45) : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? color : AppColors.foreground,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

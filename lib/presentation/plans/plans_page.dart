import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/plans_repository.dart';
import '../../domain/models/plan.dart';
import '../shared/page_header.dart';
import 'plan_form_dialog.dart';

/// Listado y edición del catálogo de planes/precios.
class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(plansListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Planes',
          title: 'Catálogo y precios',
          subtitle:
              'Edita planes, precios y features. Cambios afectan futuras facturas; las membresías existentes mantienen su plan asignado.',
          trailing: FilledButton.icon(
            onPressed: () => _create(context, ref),
            icon: const Icon(HugeIcons.strokeRoundedAdd01, size: 16),
            label: const Text('Nuevo plan'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        plansAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Error: $e',
              style: const TextStyle(color: AppColors.destructive),
            ),
          ),
          data: (plans) => _PlansGrid(plans: plans),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<PlanFormResult>(
      context: context,
      builder: (_) => const PlanFormDialog(),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(plansRepositoryProvider).upsert(
            code: result.code,
            name: result.name,
            description: result.description,
            priceMonthly: result.priceMonthly,
            features: result.features,
            displayOrder: result.displayOrder,
            isActive: result.isActive,
          );
      ref.invalidate(plansListProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan "${result.name}" creado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _PlansGrid extends ConsumerWidget {
  const _PlansGrid({required this.plans});
  final List<Plan> plans;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (plans.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: const Text(
          'No hay planes definidos. Crea el primero con "Nuevo plan".',
          style: TextStyle(color: AppColors.mutedForeground),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 1200
            ? 3
            : w >= 760
                ? 2
                : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: plans.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.95,
          ),
          itemBuilder: (_, i) => _PlanCard(plan: plans[i]),
        );
      },
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan});
  final Plan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArchived = plan.isArchived;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(
          color: isArchived
              ? AppColors.border
              : AppColors.border.withValues(alpha: 0.7),
          width: 0.6,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header con código + estado
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.muted,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  plan.code.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    fontFamily: 'monospace',
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (isArchived)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.destructive.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'ARCHIVADO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.destructive,
                    ),
                  ),
                )
              else if (!plan.isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'INACTIVO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'Acciones',
                icon: const Icon(
                  HugeIcons.strokeRoundedMoreVertical,
                  size: 16,
                  color: AppColors.mutedForeground,
                ),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Editar'),
                  ),
                  if (isArchived)
                    const PopupMenuItem(
                      value: 'restore',
                      child: Text('Restaurar'),
                    )
                  else
                    const PopupMenuItem(
                      value: 'archive',
                      child: Text('Archivar'),
                    ),
                ],
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      _edit(context, ref);
                    case 'restore':
                      _restore(context, ref);
                    case 'archive':
                      _archive(context, ref);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            plan.name,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isArchived
                  ? AppColors.mutedForeground
                  : AppColors.foreground,
              decoration:
                  isArchived ? TextDecoration.lineThrough : null,
            ),
          ),
          if (plan.description != null && plan.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              plan.description!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.mutedForeground,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatRd(plan.priceMonthly),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: plan.priceMonthly == 0
                      ? AppColors.mutedForeground
                      : AppColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '/ mes',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (plan.features.isNotEmpty) ...[
            for (final f in plan.features)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        HugeIcons.strokeRoundedCheckmarkCircle02,
                        size: 14,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.foreground,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],
          const Spacer(),
          // Footer: suscriptores
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.muted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  HugeIcons.strokeRoundedUserGroup,
                  size: 13,
                  color: plan.activeSubscribers > 0
                      ? AppColors.primary
                      : AppColors.mutedForeground,
                ),
                const SizedBox(width: 6),
                Text(
                  plan.activeSubscribers == 1
                      ? '1 suscriptor activo'
                      : '${plan.activeSubscribers} suscriptores activos',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<PlanFormResult>(
      context: context,
      builder: (_) => PlanFormDialog(existing: plan),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(plansRepositoryProvider).upsert(
            code: plan.code,
            name: result.name,
            description: result.description,
            priceMonthly: result.priceMonthly,
            features: result.features,
            displayOrder: result.displayOrder,
            isActive: result.isActive,
          );
      ref.invalidate(plansListProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan "${result.name}" actualizado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    if (plan.activeSubscribers > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se puede archivar: ${plan.activeSubscribers} suscriptor(es) activo(s). Migra primero.',
          ),
        ),
      );
      return;
    }
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Archivar plan "${plan.name}"'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'El plan dejará de aparecer en selectores. Suscriptores existentes (si los hubiera) mantienen su asignación.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Razón…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.destructive,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final v = reasonCtrl.text.trim();
              if (v.isNotEmpty) Navigator.of(context).pop(v);
            },
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(plansRepositoryProvider)
          .archive(code: plan.code, reason: reason);
      ref.invalidate(plansListProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan "${plan.name}" archivado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(plansRepositoryProvider).restore(plan.code);
      ref.invalidate(plansListProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan "${plan.name}" restaurado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/company_settings_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/services/invoice_pdf.dart';
import '../../domain/models/company_settings.dart';
import '../../domain/models/audit_log_entry.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/business_extension.dart';
import '../../domain/models/business_member.dart';
import '../../domain/models/business_overview.dart';
import '../../domain/models/business_week_trend.dart';
import '../../domain/models/customer_note.dart';
import '../../domain/models/membership_invoice.dart';
import '../../domain/models/print_failure.dart';
import '../dashboard/widgets/metric_card.dart';
import '../dashboard/widgets/status_badges.dart';
import 'customer_note_dialog.dart';
import 'grant_extension_dialog.dart';

class BusinessDetailPage extends ConsumerWidget {
  const BusinessDetailPage({required this.businessId, super.key});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // En el detalle no aplicamos el filtro global: necesitamos encontrar
    // siempre el negocio aunque sea de otro entorno que el seleccionado.
    final overviewAsync = ref.watch(platformOverviewProvider);
    final trendAsync = ref.watch(businessWeekTrendProvider);
    final printFailuresAsync =
        ref.watch(recentPrintFailuresProvider(businessId));
    final auditAsync = ref.watch(criticalAuditLogsProvider(businessId));
    final invoicesAsync = ref.watch(businessInvoicesProvider(businessId));

    return overviewAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => _ErrorBox(message: 'Error: $e'),
      data: (rows) {
        BusinessOverview? business;
        for (final r in rows) {
          if (r.id == businessId) {
            business = r;
            break;
          }
        }
        if (business == null) return const _NotFound();
        final trend = trendAsync.valueOrNull
            ?.where((t) => t.businessId == businessId)
            .cast<BusinessWeekTrend?>()
            .firstWhere((_) => true, orElse: () => null);
        return _Body(
          business: business,
          trend: trend,
          printFailuresAsync: printFailuresAsync,
          auditAsync: auditAsync,
          invoicesAsync: invoicesAsync,
        );
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.business,
    required this.trend,
    required this.printFailuresAsync,
    required this.auditAsync,
    required this.invoicesAsync,
  });

  final BusinessOverview business;
  final BusinessWeekTrend? trend;
  final AsyncValue<List<PrintFailure>> printFailuresAsync;
  final AsyncValue<List<AuditLogEntry>> auditAsync;
  final AsyncValue<List<MembershipInvoice>> invoicesAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extensionsAsync =
        ref.watch(businessExtensionsProvider(business.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(business: business),
        const SizedBox(height: 24),
        _IdentityStrip(business: business),
        const SizedBox(height: 24),
        const _SectionTitle('Métricas de hoy'),
        const SizedBox(height: 12),
        _TodayMetrics(business: business, trend: trend),
        const SizedBox(height: 28),
        _FiscalAndAgent(business: business),
        const SizedBox(height: 28),
        _PrintFailuresSection(asyncFailures: printFailuresAsync),
        const SizedBox(height: 28),
        _TeamSection(business: business),
        const SizedBox(height: 28),
        _InvoicesSection(business: business, invoicesAsync: invoicesAsync),
        const SizedBox(height: 28),
        _ExtensionsSection(
          business: business,
          extensionsAsync: extensionsAsync,
        ),
        const SizedBox(height: 28),
        _NotesSection(business: business),
        const SizedBox(height: 28),
        _AuditSection(asyncLogs: auditAsync),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends ConsumerWidget {
  const _Header({required this.business});
  final BusinessOverview business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => context.go('/'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                HugeIcons.strokeRoundedArrowLeft01,
                size: 14,
                color: AppColors.mutedForeground,
              ),
              SizedBox(width: 4),
              Text(
                'Vista global',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 760;
            final left = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPrimary,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppColors.shadowElegant,
                  ),
                  child: const Icon(
                    HugeIcons.strokeRoundedBuilding03,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        business.name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        business.domain,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            final right = Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _EnvPill(env: business.environment),
                PlanBadge(plan: business.plan),
                AgentBadge(status: business.agentStatus),
                NcfBadge(status: business.ncfStatus),
                _StatusPill(active: business.isActive),
                OutlinedButton.icon(
                  onPressed: () => _editMembership(context, ref),
                  icon: const Icon(
                    HugeIcons.strokeRoundedCalendar03,
                    size: 14,
                  ),
                  label: const Text('Editar membresía'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _grantExtension(context, ref),
                  icon: const Icon(
                    HugeIcons.strokeRoundedGift,
                    size: 14,
                  ),
                  label: const Text('Dar prórroga'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _toggleEnv(context, ref),
                  icon: const Icon(
                    HugeIcons.strokeRoundedExchange01,
                    size: 14,
                  ),
                  label: Text(
                    business.environment == BusinessEnvironment.production
                        ? 'Marcar Sandbox'
                        : 'Marcar Producción',
                  ),
                ),
                _LifecycleMenu(business: business),
              ],
            );

            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [left, const SizedBox(height: 14), right],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [Expanded(child: left), right],
            );
          },
        ),
      ],
    );
  }

  Future<void> _editMembership(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_MembershipEditResult>(
      context: context,
      builder: (_) => _MembershipDialog(
        currentPlan: business.plan,
        currentEndDate: business.planEndDate,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(dashboardRepositoryProvider).updateBusinessMembership(
            businessId: business.id,
            planType: result.plan.raw,
            endDate: result.endDate,
            status: result.status,
          );
      ref.invalidate(platformOverviewProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Membresía de ${business.name} actualizada (${result.plan.label}, ${result.statusLabel}).',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _grantExtension(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<GrantExtensionResult>(
      context: context,
      builder: (_) => GrantExtensionDialog(businessName: business.name),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(dashboardRepositoryProvider).grantExtension(
            businessId: business.id,
            type: result.type,
            days: result.days,
            amount: result.amount,
            reason: result.reason,
            customerMessage: result.customerMessage,
          );
      ref.invalidate(businessExtensionsProvider(business.id));
      ref.invalidate(platformOverviewProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.type.label} otorgada a ${business.name}.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _toggleEnv(BuildContext context, WidgetRef ref) async {
    final next = business.environment == BusinessEnvironment.production
        ? BusinessEnvironment.sandbox
        : BusinessEnvironment.production;
    try {
      await ref
          .read(dashboardRepositoryProvider)
          .setBusinessEnvironment(business.id, next);
      ref.invalidate(platformOverviewProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${business.name} marcado como ${next.label}.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

}

// ---------------------------------------------------------------------------
// Menú de ciclo de vida (Desactivar / Reactivar / Eliminar)
// ---------------------------------------------------------------------------

class _LifecycleMenu extends ConsumerWidget {
  const _LifecycleMenu({required this.business});

  final BusinessOverview business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = business.isActive;
    return PopupMenuButton<String>(
      tooltip: 'Acciones de cuenta',
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        if (active)
          const PopupMenuItem(
            value: 'deactivate',
            child: _MenuRow(
              icon: HugeIcons.strokeRoundedPowerSocket02,
              label: 'Desactivar cuenta',
              color: AppColors.warning,
            ),
          )
        else
          const PopupMenuItem(
            value: 'activate',
            child: _MenuRow(
              icon: HugeIcons.strokeRoundedPowerSocket02,
              label: 'Reactivar cuenta',
              color: AppColors.success,
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: _MenuRow(
            icon: HugeIcons.strokeRoundedDelete02,
            label: 'Eliminar permanentemente',
            color: AppColors.destructive,
          ),
        ),
      ],
      onSelected: (action) async {
        switch (action) {
          case 'deactivate':
            await _deactivate(context, ref);
            break;
          case 'activate':
            await _activate(context, ref);
            break;
          case 'delete':
            await _delete(context, ref);
            break;
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.destructive.withValues(alpha: 0.08),
          border: Border.all(
            color: AppColors.destructive.withValues(alpha: 0.30),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              HugeIcons.strokeRoundedMoreVertical,
              size: 14,
              color: AppColors.destructive,
            ),
            SizedBox(width: 6),
            Text(
              'Cuenta',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.destructive,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deactivate(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Desactivar cuenta',
        description:
            'La cuenta quedará inactiva: no podrá acceder al POS hasta que la reactives. Los datos se conservan.',
        confirmLabel: 'Desactivar',
        confirmColor: AppColors.warning,
      ),
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(dashboardRepositoryProvider)
          .deactivateBusiness(business.id, reason);
      ref.invalidate(platformOverviewProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${business.name} desactivado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(dashboardRepositoryProvider)
          .activateBusiness(business.id);
      ref.invalidate(platformOverviewProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${business.name} reactivado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_DeleteResult>(
      context: context,
      builder: (_) => _DeleteDialog(businessName: business.name),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(dashboardRepositoryProvider).deleteBusiness(
            businessId: business.id,
            confirmation: result.confirmation,
            reason: result.reason,
            force: result.force,
          );
      ref.invalidate(platformOverviewProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${business.name} eliminado permanentemente.')),
      );
      context.go('/');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
    required this.confirmColor,
  });

  final String title;
  final String description;
  final String confirmLabel;
  final Color confirmColor;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();
  bool _enabled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.description,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 14),
            const _DialogLabel('Razón (obligatoria)'),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                hintText: 'Explica brevemente por qué…',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                setState(() => _enabled = v.trim().isNotEmpty);
              },
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
            backgroundColor: widget.confirmColor,
            foregroundColor: Colors.white,
          ),
          onPressed: _enabled
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _DeleteResult {
  const _DeleteResult({
    required this.confirmation,
    required this.reason,
    required this.force,
  });
  final String confirmation;
  final String reason;
  final bool force;
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.businessName});
  final String businessName;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _nameController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _force = false;
  bool get _enabled =>
      _nameController.text.trim() == widget.businessName &&
      _reasonController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: const [
          Icon(
            HugeIcons.strokeRoundedAlert02,
            color: AppColors.destructive,
            size: 18,
          ),
          SizedBox(width: 8),
          Text('Eliminar permanentemente'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.destructive.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppColors.destructive.withValues(alpha: 0.25),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Esta acción es irreversible. Se borrará el negocio, su membresía y facturas de membresía. Si existen registros en otras tablas con restricción (órdenes, pagos), la operación fallará y deberás limpiarlos antes.',
                style: TextStyle(fontSize: 12, color: AppColors.foreground),
              ),
            ),
            const SizedBox(height: 14),
            const _DialogLabel('Escribe el nombre exacto del negocio'),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.businessName,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            const _DialogLabel('Razón (obligatoria)'),
            const SizedBox(height: 6),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                hintText: 'Ej: cuenta de prueba duplicada, request del owner…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _force,
              onChanged: (v) => setState(() => _force = v),
              title: const Text(
                'Forzar (saltar triggers y validaciones)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.destructive,
                ),
              ),
              subtitle: const Text(
                'Necesario si el negocio tiene cajas firmadas o data fiscal protegida. Saltea todos los triggers user-defined durante el borrado. Queda registrado en audit.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.mutedForeground,
                ),
              ),
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeThumbColor: AppColors.destructive,
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
          onPressed: _enabled
              ? () => Navigator.of(context).pop(
                    _DeleteResult(
                      confirmation: _nameController.text.trim(),
                      reason: _reasonController.text.trim(),
                      force: _force,
                    ),
                  )
              : null,
          child: const Text('Eliminar permanentemente'),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = active
        ? (AppColors.success.withValues(alpha: 0.10), AppColors.success)
        : (AppColors.destructive.withValues(alpha: 0.10),
            AppColors.destructive);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        active ? 'ACTIVO' : 'INACTIVO',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: fg,
        ),
      ),
    );
  }
}

class _EnvPill extends StatelessWidget {
  const _EnvPill({required this.env});
  final BusinessEnvironment env;

  @override
  Widget build(BuildContext context) {
    final isProd = env == BusinessEnvironment.production;
    final color = isProd ? AppColors.success : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            env.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Identity strip
// ---------------------------------------------------------------------------

class _IdentityStrip extends StatelessWidget {
  const _IdentityStrip({required this.business});
  final BusinessOverview business;

  @override
  Widget build(BuildContext context) {
    final planDays =
        business.planEndDate == null ? null : daysUntil(business.planEndDate);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double maxW = constraints.maxWidth;
          final int cols;
          final double ratio;
          if (maxW >= 720) {
            cols = 4;
            ratio = 3.0;
          } else if (maxW >= 480) {
            cols = 2;
            ratio = 3.5;
          } else {
            cols = 1;
            ratio = 5.0;
          }
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 14,
            childAspectRatio: ratio,
            children: [
              _Field(label: 'Tipo', value: business.businessType ?? '—'),
              _Field(
                label: 'ID',
                value: business.id.substring(0, 8),
                monospace: true,
              ),
              _Field(
                label: 'Plan',
                value: business.plan.label,
              ),
              _Field(
                label: 'Membresía',
                value: planDays == null
                    ? '—'
                    : (planDays < 0
                        ? 'Vencida hace ${-planDays}d'
                        : '$planDays días restantes'),
                highlight: planDays != null && planDays < 7,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.monospace = false,
    this.highlight = false,
  });
  final String label;
  final String value;
  final bool monospace;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: monospace ? 'monospace' : null,
            color: highlight ? AppColors.destructive : AppColors.foreground,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Metrics today
// ---------------------------------------------------------------------------

class _TodayMetrics extends StatelessWidget {
  const _TodayMetrics({required this.business, required this.trend});
  final BusinessOverview business;
  final BusinessWeekTrend? trend;

  @override
  Widget build(BuildContext context) {
    final ticketAvg =
        business.salesToday > 0 ? business.revenueToday / business.salesToday : 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxW = constraints.maxWidth;
        final int cols;
        final double ratio;
        if (maxW >= 1100) {
          cols = 4;
          ratio = 1.4;
        } else if (maxW >= 640) {
          cols = 2;
          ratio = 1.35;
        } else {
          cols = 1;
          ratio = 2.8;
        }
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: ratio,
          children: [
            MetricCard(
              label: 'Ingresos hoy',
              value: formatRd(business.revenueToday),
              sublabel: '${business.salesToday} ventas',
              icon: HugeIcons.strokeRoundedDollarCircle,
              variant: MetricVariant.accent,
            ),
            MetricCard(
              label: 'Ticket promedio',
              value: formatRd(ticketAvg),
              icon: HugeIcons.strokeRoundedInvoice03,
              variant: MetricVariant.primary,
            ),
            MetricCard(
              label: 'Cajas abiertas',
              value: '${business.openSessions}',
              sublabel: '${business.openTables} mesas activas',
              icon: HugeIcons.strokeRoundedDashboardCircle,
            ),
            MetricCard(
              label: 'Semana actual',
              value: formatRd(trend?.weekRevenue ?? 0),
              sublabel: trend != null && trend!.lastWeekRevenue > 0
                  ? 'vs ${formatRd(trend!.lastWeekRevenue)} prev.'
                  : '7 últimos días',
              icon: HugeIcons.strokeRoundedDollarCircle,
              variant: MetricVariant.success,
              trend: trend?.trendPct,
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Fiscal + Agent panels
// ---------------------------------------------------------------------------

class _FiscalAndAgent extends StatelessWidget {
  const _FiscalAndAgent({required this.business});
  final BusinessOverview business;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 760;
        final children = [
          _FiscalCard(business: business),
          SizedBox(width: stack ? 0 : 20, height: stack ? 16 : 0),
          _AgentCard(business: business),
        ];
        if (stack) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[0]),
              children[1],
              Expanded(child: children[2]),
            ],
          ),
        );
      },
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.title, required this.icon, required this.trailing, required this.children});
  final String title;
  final IconData icon;
  final Widget trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
              ),
              trailing,
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _FiscalCard extends StatelessWidget {
  const _FiscalCard({required this.business});
  final BusinessOverview business;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'Facturación fiscal',
      icon: HugeIcons.strokeRoundedInvoice03,
      trailing: NcfBadge(status: business.ncfStatus),
      children: [
        _Row(label: 'Comprobantes emitidos hoy',
            value: '${business.ncfIssuedToday}'),
        _Row(label: 'NCF disponibles',
            value: formatInt(business.ncfAvailable),
            highlight: business.ncfStatus != NcfStatus.ok),
        _Row(label: 'ITBIS estimado (18%)',
            value: formatRd(business.revenueToday * 0.18)),
        if (business.ncfStatus != NcfStatus.ok) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Las secuencias NCF están bajas. Coordinar con el dueño para solicitar nuevas a la DGII.',
              style: TextStyle(fontSize: 12, color: AppColors.foreground),
            ),
          ),
        ],
      ],
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.business});
  final BusinessOverview business;

  double get _successRate {
    if (business.printJobsToday == 0) return 0;
    final ok = business.printJobsToday - business.printFailures24h;
    return (ok / business.printJobsToday) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'Agente local',
      icon: HugeIcons.strokeRoundedWifi01,
      trailing: AgentBadge(status: business.agentStatus),
      children: [
        _Row(label: 'Nombre', value: business.agentName ?? '—'),
        _Row(
            label: 'Último ping',
            value: formatRelative(business.agentLastSeen)),
        _Row(
            label: 'Trabajos de impresión hoy',
            value: '${business.printJobsToday}'),
        _Row(
            label: 'Tasa de éxito',
            value: business.printJobsToday == 0
                ? '—'
                : '${_successRate.toStringAsFixed(1)}%',
            highlight: business.printJobsToday > 0 && _successRate < 90),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: highlight ? AppColors.destructive : AppColors.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Print failures section
// ---------------------------------------------------------------------------

class _PrintFailuresSection extends StatelessWidget {
  const _PrintFailuresSection({required this.asyncFailures});
  final AsyncValue<List<PrintFailure>> asyncFailures;

  @override
  Widget build(BuildContext context) {
    return asyncFailures.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle('Fallas de impresión recientes',
                icon: HugeIcons.strokeRoundedPrinter),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.border, width: 0.6),
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppColors.shadowCard,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    _PrintFailureRow(f: rows[i]),
                    if (i < rows.length - 1)
                      const Divider(
                          height: 1, thickness: 1, color: AppColors.border),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PrintFailureRow extends StatelessWidget {
  const _PrintFailureRow({required this.f});
  final PrintFailure f;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 450;
          final timeWidget = Text(
            formatRelative(f.createdAt),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.mutedForeground,
            ),
          );
          final contentWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${f.printerName} (${f.printerIp}${f.printerPort != null ? ":${f.printerPort}" : ""})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                f.error ?? '—',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.destructive,
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                timeWidget,
                const SizedBox(height: 6),
                contentWidget,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: timeWidget,
              ),
              Expanded(
                child: contentWidget,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team section (cliente y miembros)
// ---------------------------------------------------------------------------

class _TeamSection extends ConsumerWidget {
  const _TeamSection({required this.business});

  final BusinessOverview business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(businessTeamProvider(business.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          'Cliente y equipo',
          icon: HugeIcons.strokeRoundedUserGroup,
        ),
        const SizedBox(height: 12),
        teamAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => _ErrorBox(message: 'Error: $e'),
          data: (members) {
            if (members.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'No hay usuarios asociados a este negocio.',
                  style: TextStyle(color: AppColors.mutedForeground),
                ),
              );
            }
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
                children: [
                  for (var i = 0; i < members.length; i++) ...[
                    _MemberRow(member: members[i]),
                    if (i < members.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.border,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});
  final BusinessMember member;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar circular con inicial.
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: member.isOwner
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.muted,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initial(member.displayName),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: member.isOwner
                    ? AppColors.primary
                    : AppColors.foreground,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        member.displayName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
                    if (member.isOwner)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color:
                              AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'OWNER',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.muted,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          member.role.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                _ContactRow(
                  icon: HugeIcons.strokeRoundedMail01,
                  value: member.email ?? '—',
                  highlight: member.email != null && !member.emailVerified
                      ? 'No verificado'
                      : null,
                ),
                if (member.phone != null && member.phone!.isNotEmpty)
                  _ContactRow(
                    icon: HugeIcons.strokeRoundedCall,
                    value: member.phone!,
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    if (member.lastSignInAt != null)
                      _MetaLine(
                        label: 'Último login',
                        value: formatRelative(member.lastSignInAt),
                      ),
                    if (member.userCreatedAt != null)
                      _MetaLine(
                        label: 'Registrado',
                        value: formatRelative(member.userCreatedAt),
                      ),
                    if (member.isOwner && member.endDate != null)
                      _MetaLine(
                        label: 'Membresía hasta',
                        value: formatRelative(member.endDate),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initial(String s) {
    final t = s.trim();
    if (t.isEmpty) return '?';
    return t.substring(0, 1).toUpperCase();
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.value,
    this.highlight,
  });
  final IconData icon;
  final String value;
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: AppColors.mutedForeground),
          const SizedBox(width: 6),
          Flexible(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.foreground,
                height: 1.3,
              ),
            ),
          ),
          if (highlight != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                highlight!,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.mutedForeground,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: AppColors.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Invoices section
// ---------------------------------------------------------------------------

class _InvoicesSection extends ConsumerWidget {
  const _InvoicesSection({required this.business, required this.invoicesAsync});
  final BusinessOverview business;
  final AsyncValue<List<MembershipInvoice>> invoicesAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: _SectionTitle('Facturación de membresía',
                  icon: HugeIcons.strokeRoundedInvoice03),
            ),
            OutlinedButton.icon(
              onPressed: () => _generate(context, ref),
              icon: const Icon(HugeIcons.strokeRoundedFile02, size: 14),
              label: const Text('Nueva factura'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        invoicesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => _ErrorBox(message: 'Error: $e'),
          data: (rows) {
            if (rows.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(
                    color: AppColors.border,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Este negocio no tiene facturas generadas.',
                  style: TextStyle(color: AppColors.mutedForeground),
                ),
              );
            }
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
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    _InvoiceRow(invoice: rows[i]),
                    if (i < rows.length - 1)
                      const Divider(
                          height: 1, thickness: 1, color: AppColors.border),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    try {
      final inv = await ref.read(billingRepositoryProvider).generate(business.id);
      ref.invalidate(businessInvoicesProvider(business.id));
      ref.invalidate(billingOverviewProvider);
      ref.invalidate(billingMetricsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura ${inv.invoiceNumber} generada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _InvoiceRow extends ConsumerWidget {
  const _InvoiceRow({required this.invoice});
  final MembershipInvoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref
        .watch(companySettingsProvider)
        .valueOrNull
        ?? CompanySettings.fallback;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 500;
          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      invoice.invoiceNumber,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground,
                      ),
                    ),
                    _MiniInvoiceStatus(status: invoice.status),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Vence ${formatRelative(invoice.dueDate)} · ${invoice.planType.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ),
                    Text(
                      formatRd(invoice.total),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                        color: AppColors.foreground,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        HugeIcons.strokeRoundedMoreVertical,
                        size: 16,
                        color: AppColors.mutedForeground,
                      ),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'pdf', child: Text('Ver PDF')),
                        PopupMenuItem(
                            value: 'share', child: Text('Compartir / WhatsApp')),
                      ],
                      onSelected: (action) async {
                        if (action == 'pdf') {
                          await previewInvoicePdf(invoice, company: company);
                        } else if (action == 'share') {
                          await shareInvoicePdf(invoice, company: company);
                        }
                      },
                    ),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              SizedBox(
                width: 130,
                child: Text(
                  invoice.invoiceNumber,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Vence ${formatRelative(invoice.dueDate)} · ${invoice.planType.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
              Text(
                formatRd(invoice.total),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(width: 12),
              _MiniInvoiceStatus(status: invoice.status),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: const Icon(
                  HugeIcons.strokeRoundedMoreVertical,
                  size: 16,
                  color: AppColors.mutedForeground,
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pdf', child: Text('Ver PDF')),
                  PopupMenuItem(
                      value: 'share', child: Text('Compartir / WhatsApp')),
                ],
                onSelected: (action) async {
                  if (action == 'pdf') {
                    await previewInvoicePdf(invoice, company: company);
                  } else if (action == 'share') {
                    await shareInvoicePdf(invoice, company: company);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MiniInvoiceStatus extends StatelessWidget {
  const _MiniInvoiceStatus({required this.status});
  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      InvoiceStatus.paid => (
          AppColors.success.withValues(alpha: 0.10),
          AppColors.success
        ),
      InvoiceStatus.pending => (
          AppColors.warning.withValues(alpha: 0.15),
          AppColors.warning
        ),
      InvoiceStatus.expired => (
          AppColors.destructive.withValues(alpha: 0.10),
          AppColors.destructive
        ),
      InvoiceStatus.voided => (AppColors.muted, AppColors.mutedForeground),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: fg,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extensions section (prórrogas y créditos)
// ---------------------------------------------------------------------------

class _ExtensionsSection extends ConsumerWidget {
  const _ExtensionsSection({
    required this.business,
    required this.extensionsAsync,
  });

  final BusinessOverview business;
  final AsyncValue<List<BusinessExtension>> extensionsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          'Prórrogas y créditos',
          icon: HugeIcons.strokeRoundedGift,
        ),
        const SizedBox(height: 12),
        extensionsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => _ErrorBox(message: 'Error: $e'),
          data: (rows) {
            if (rows.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'No se han otorgado prórrogas ni créditos a este negocio.',
                  style: TextStyle(color: AppColors.mutedForeground),
                ),
              );
            }
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
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    _ExtensionRow(
                      ext: rows[i],
                      onRevert: () => _revert(context, ref, rows[i]),
                    ),
                    if (i < rows.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.border,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _revert(
    BuildContext context,
    WidgetRef ref,
    BusinessExtension ext,
  ) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Revertir prórroga'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Se revertirá ${ext.type.label.toLowerCase()} otorgada '
                '${formatRelative(ext.grantedAt)}. '
                'Si extendió la fecha de corte, ésta se restaurará.',
                style: const TextStyle(
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
                  hintText: 'Razón de la reversión…',
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
            child: const Text('Revertir'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    if (reason == null || !context.mounted) return;
    try {
      await ref.read(dashboardRepositoryProvider).revertExtension(
            extensionId: ext.id,
            reason: reason,
          );
      ref.invalidate(businessExtensionsProvider(business.id));
      ref.invalidate(platformOverviewProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prórroga revertida.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _ExtensionRow extends StatelessWidget {
  const _ExtensionRow({required this.ext, required this.onRevert});

  final BusinessExtension ext;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (ext.type) {
      ExtensionType.trialExtension => (AppColors.accent, 'TRIAL +${ext.daysGranted}d'),
      ExtensionType.paymentGrace => (AppColors.warning, 'GRACIA +${ext.daysGranted}d'),
      ExtensionType.freeCredit => (
          AppColors.success,
          'CRÉDITO ${formatRd(ext.amount ?? 0)}',
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: ext.isReverted ? 0.06 : 0.10,
              ),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: ext.isReverted ? AppColors.mutedForeground : color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ext.reason,
                  style: TextStyle(
                    fontSize: 13,
                    color: ext.isReverted
                        ? AppColors.mutedForeground
                        : AppColors.foreground,
                    decoration: ext.isReverted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [
                      if (ext.grantedByName != null) ext.grantedByName!,
                      formatRelative(ext.grantedAt),
                      if (ext.effectiveUntil != null)
                        'hasta ${formatRelative(ext.effectiveUntil)}',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
                if (ext.isReverted) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Revertida · ${ext.revertedReason ?? ""}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.destructive,
                    ),
                  ),
                ],
                if (ext.isApplied) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Aplicado a factura ${ext.appliedToInvoiceNumber ?? ext.appliedToInvoiceId}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (ext.isActive)
            TextButton(
              onPressed: onRevert,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.destructive,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Revertir', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notes section (CRM ligero)
// ---------------------------------------------------------------------------

class _NotesSection extends ConsumerWidget {
  const _NotesSection({required this.business});

  final BusinessOverview business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(customerNotesProvider(business.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: _SectionTitle(
                'Notas internas',
                icon: HugeIcons.strokeRoundedNote,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _create(context, ref),
              icon: const Icon(HugeIcons.strokeRoundedAdd01, size: 14),
              label: const Text('Nueva nota'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        notesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => _ErrorBox(message: 'Error: $e'),
          data: (notes) {
            if (notes.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'No hay notas internas para este negocio.',
                  style: TextStyle(color: AppColors.mutedForeground),
                ),
              );
            }
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
                children: [
                  for (var i = 0; i < notes.length; i++) ...[
                    _NoteRow(
                      note: notes[i],
                      onTogglePin: () => _togglePin(context, ref, notes[i]),
                      onEdit: notes[i].isOwn
                          ? () => _edit(context, ref, notes[i])
                          : null,
                      onDelete: notes[i].isOwn
                          ? () => _delete(context, ref, notes[i])
                          : null,
                    ),
                    if (i < notes.length - 1)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.border,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<CustomerNoteResult>(
      context: context,
      builder: (_) => const CustomerNoteDialog(),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(dashboardRepositoryProvider).createCustomerNote(
            businessId: business.id,
            category: result.category,
            body: result.body,
            pinned: result.pinned,
          );
      ref.invalidate(customerNotesProvider(business.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nota creada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    CustomerNote note,
  ) async {
    final result = await showDialog<CustomerNoteResult>(
      context: context,
      builder: (_) => CustomerNoteDialog(existing: note),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(dashboardRepositoryProvider).updateCustomerNote(
            noteId: note.id,
            category: result.category,
            body: result.body,
            pinned: result.pinned,
          );
      ref.invalidate(customerNotesProvider(business.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nota actualizada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _togglePin(
    BuildContext context,
    WidgetRef ref,
    CustomerNote note,
  ) async {
    try {
      await ref.read(dashboardRepositoryProvider).toggleCustomerNotePin(note.id);
      ref.invalidate(customerNotesProvider(business.id));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CustomerNote note,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar nota'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.destructive,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(dashboardRepositoryProvider).deleteCustomerNote(note.id);
      ref.invalidate(customerNotesProvider(business.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nota borrada.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.onTogglePin,
    this.onEdit,
    this.onDelete,
  });

  final CustomerNote note;
  final VoidCallback onTogglePin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  Color get _categoryColor {
    switch (note.category) {
      case NoteCategory.billingIssue:
      case NoteCategory.complaint:
      case NoteCategory.churnRisk:
      case NoteCategory.churnReason:
      case NoteCategory.incident:
        return AppColors.destructive;
      case NoteCategory.featureRequest:
      case NoteCategory.salesFollowup:
        return AppColors.accent;
      case NoteCategory.compliment:
        return AppColors.success;
      case NoteCategory.training:
        return AppColors.warning;
      case NoteCategory.general:
        return AppColors.mutedForeground;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _categoryColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              note.category.label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _categoryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.body,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.foreground,
                    height: 1.35,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    [
                      if (note.authorName != null) note.authorName!,
                      formatRelative(note.createdAt),
                      if (note.wasEdited) 'editada',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: note.pinned ? 'Desfijar' : 'Fijar arriba',
            icon: Icon(
              note.pinned
                  ? HugeIcons.strokeRoundedPin
                  : HugeIcons.strokeRoundedPinLocation01,
              size: 16,
              color: note.pinned ? AppColors.accent : AppColors.mutedForeground,
            ),
            onPressed: onTogglePin,
          ),
          if (onEdit != null || onDelete != null)
            PopupMenuButton<String>(
              icon: const Icon(
                HugeIcons.strokeRoundedMoreVertical,
                size: 16,
                color: AppColors.mutedForeground,
              ),
              itemBuilder: (_) => [
                if (onEdit != null)
                  const PopupMenuItem(value: 'edit', child: Text('Editar')),
                if (onDelete != null)
                  const PopupMenuItem(value: 'delete', child: Text('Borrar')),
              ],
              onSelected: (action) {
                if (action == 'edit') onEdit?.call();
                if (action == 'delete') onDelete?.call();
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Audit section
// ---------------------------------------------------------------------------

class _AuditSection extends StatelessWidget {
  const _AuditSection({required this.asyncLogs});
  final AsyncValue<List<AuditLogEntry>> asyncLogs;

  @override
  Widget build(BuildContext context) {
    return asyncLogs.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (logs) {
        if (logs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle('Auditoría reciente'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.border, width: 0.6),
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppColors.shadowCard,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < logs.length; i++) ...[
                    _AuditRow(log: logs[i]),
                    if (i < logs.length - 1)
                      const Divider(
                          height: 1, thickness: 1, color: AppColors.border),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.log});
  final AuditLogEntry log;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (log.severity) {
      AuditSeverity.critical => (
          AppColors.destructive.withValues(alpha: 0.10),
          AppColors.destructive
        ),
      AuditSeverity.warning => (
          AppColors.warning.withValues(alpha: 0.15),
          AppColors.warning
        ),
      AuditSeverity.info => (AppColors.muted, AppColors.mutedForeground),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              log.action.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: fg,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (log.reason != null && log.reason!.isNotEmpty)
                  Text(
                    log.reason!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.foreground,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [
                      if (log.refTable != null) log.refTable!,
                      if (log.userName != null) log.userName!,
                      formatRelative(log.createdAt),
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Auxiliares
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AppColors.mutedForeground),
          const SizedBox(width: 6),
        ],
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: AppColors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Negocio no encontrado.',
              style: TextStyle(color: AppColors.mutedForeground, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => GoRouter.of(context).go('/'),
              child: const Text('Volver al dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.destructive, fontSize: 13),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Membership edit dialog
// ---------------------------------------------------------------------------

class _MembershipEditResult {
  const _MembershipEditResult({
    required this.plan,
    required this.endDate,
    required this.status,
  });

  /// Plan elegido.
  final PlanType plan;

  /// Nueva fecha de corte.
  final DateTime endDate;

  /// 'active' | 'expired' | 'canceled' (lo que el RPC espera).
  final String status;

  String get statusLabel {
    switch (status) {
      case 'active':
        return 'Pagada';
      case 'expired':
        return 'Vencida';
      case 'canceled':
        return 'Cancelada';
      default:
        return status;
    }
  }
}

class _MembershipDialog extends StatefulWidget {
  const _MembershipDialog({
    required this.currentPlan,
    required this.currentEndDate,
  });

  final PlanType currentPlan;
  final DateTime? currentEndDate;

  @override
  State<_MembershipDialog> createState() => _MembershipDialogState();
}

class _MembershipDialogState extends State<_MembershipDialog> {
  late PlanType _plan;
  late DateTime _endDate;
  late String _status;

  @override
  void initState() {
    super.initState();
    _plan = widget.currentPlan == PlanType.unknown
        ? PlanType.basic
        : widget.currentPlan;
    _endDate = widget.currentEndDate ??
        DateTime.now().add(const Duration(days: 30));
    _status = 'active';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      helpText: 'Fecha de corte',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      locale: const Locale('es'),
    );
    if (picked != null) {
      setState(() {
        // Mantener la hora del end_date original para no perder precisión.
        _endDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _endDate.hour,
          _endDate.minute,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${_endDate.day.toString().padLeft(2, "0")}/'
        '${_endDate.month.toString().padLeft(2, "0")}/'
        '${_endDate.year}';

    return AlertDialog(
      title: const Text('Editar membresía'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DialogLabel('Plan'),
            const SizedBox(height: 6),
            DropdownButtonFormField<PlanType>(
              initialValue: _plan,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: PlanType.trial, child: Text('Trial')),
                DropdownMenuItem(value: PlanType.free, child: Text('Free')),
                DropdownMenuItem(value: PlanType.basic, child: Text('Basic')),
                DropdownMenuItem(value: PlanType.pro, child: Text('Pro')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _plan = v);
              },
            ),
            const SizedBox(height: 16),
            const _DialogLabel('Fecha de corte'),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.muted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      HugeIcons.strokeRoundedCalendar03,
                      size: 16,
                      color: AppColors.mutedForeground,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _DialogLabel('Estado'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                _StatusChip(
                  label: 'Pagada',
                  color: AppColors.success,
                  selected: _status == 'active',
                  onTap: () => setState(() => _status = 'active'),
                ),
                _StatusChip(
                  label: 'Vencida',
                  color: AppColors.destructive,
                  selected: _status == 'expired',
                  onTap: () => setState(() => _status = 'expired'),
                ),
                _StatusChip(
                  label: 'Cancelada',
                  color: AppColors.mutedForeground,
                  selected: _status == 'canceled',
                  onTap: () => setState(() => _status = 'canceled'),
                ),
              ],
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
          onPressed: () => Navigator.of(context).pop(
            _MembershipEditResult(
              plan: _plan,
              endDate: _endDate,
              status: _status,
            ),
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _DialogLabel extends StatelessWidget {
  const _DialogLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.mutedForeground,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

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
            color: selected
                ? color.withValues(alpha: 0.45)
                : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? color : AppColors.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

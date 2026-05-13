import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/services/invoice_pdf.dart';
import '../../domain/models/audit_log_entry.dart';
import '../../domain/models/business_environment.dart';
import '../../domain/models/business_overview.dart';
import '../../domain/models/business_week_trend.dart';
import '../../domain/models/membership_invoice.dart';
import '../../domain/models/print_failure.dart';
import '../dashboard/widgets/metric_card.dart';
import '../dashboard/widgets/status_badges.dart';

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
        _InvoicesSection(business: business, invoicesAsync: invoicesAsync),
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
                OutlinedButton.icon(
                  onPressed: () => _toggle(context, ref),
                  icon: const Icon(
                    HugeIcons.strokeRoundedPowerSocket02,
                    size: 14,
                  ),
                  label: Text(
                    business.isActive ? 'Desactivar' : 'Activar',
                  ),
                ),
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

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final wasActive = business.isActive;
    try {
      await ref
          .read(dashboardRepositoryProvider)
          .toggleBusinessStatus(business.id);
      ref.invalidate(platformOverviewProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasActive
                ? '${business.name} desactivado.'
                : '${business.name} activado.',
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
          final cols = constraints.maxWidth >= 720 ? 4 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 14,
            // Más holgado para que tipos largos como "Cafetería / Panadería" no se corten.
            childAspectRatio: cols == 4 ? 3.0 : 4.0,
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
        final cols = constraints.maxWidth >= 1100 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          // 1.35 en 2 cols deja unos 8 px extra de altura para que el
          // sublabel no quede recortado por overflow de fracciones de píxel.
          childAspectRatio: cols == 4 ? 1.4 : 1.35,
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
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: children[0]),
            children[1],
            Expanded(child: children[2]),
          ],
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              formatRelative(f.createdAt),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: Column(
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
            ),
          ),
        ],
      ),
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

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice});
  final MembershipInvoice invoice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
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
                await previewInvoicePdf(invoice);
              } else if (action == 'share') {
                await shareInvoicePdf(invoice);
              }
            },
          ),
        ],
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

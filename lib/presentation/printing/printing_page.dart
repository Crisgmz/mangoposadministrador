import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/print_health_repository.dart';
import '../../domain/models/print_agent_health.dart';
import '../../domain/models/print_job.dart';
import '../shared/business_avatar.dart';
import '../shared/page_header.dart';

/// NOC de impresión (PRD-12 Fase 2).
///
/// - 4 KPIs: agentes en línea / jobs pendientes / imprimiendo / fallos 1h.
/// - Ranking top 10 negocios con más fallas última hora.
/// - Grid de agentes con dot coloreado por heartbeat.
/// - Tabla de jobs filtrable con acciones (retry / cancel).
class PrintingPage extends ConsumerWidget {
  const PrintingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(printHealthSummaryProvider);
    final agentsAsync = ref.watch(printAgentsProvider);
    final jobsAsync = ref.watch(printJobsProvider);
    final topAsync = ref.watch(printTopFailuresProvider);
    final query = ref.watch(printJobsQueryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Impresión',
          title: 'Agentes y trabajos',
          subtitle: 'Salud de la cola de impresión cross-tenant.',
          trailing: OutlinedButton.icon(
            onPressed: () {
              ref.invalidate(printHealthSummaryProvider);
              ref.invalidate(printAgentsProvider);
              ref.invalidate(printJobsProvider);
              ref.invalidate(printTopFailuresProvider);
            },
            icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
            label: const Text('Actualizar'),
          ),
        ),
        const SizedBox(height: 24),
        summaryAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error métricas: $e'),
          data: (s) => _SummaryGrid(s: s),
        ),
        const SizedBox(height: 24),
        topAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error ranking: $e'),
          data: (rows) => _TopFailures(rows: rows),
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Agentes locales'),
        const SizedBox(height: 12),
        agentsAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error agentes: $e'),
          data: (rows) => _AgentsGrid(rows: rows),
        ),
        const SizedBox(height: 28),
        _JobsSection(query: query, jobsAsync: jobsAsync),
      ],
    );
  }
}

Widget _loader() => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );

Widget _err(String msg) => Padding(
      padding: const EdgeInsets.all(16),
      child: Text(msg,
          style: const TextStyle(color: AppColors.destructive, fontSize: 13)),
    );

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: AppColors.mutedForeground,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary KPIs
// ---------------------------------------------------------------------------

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.s});
  final PrintHealthSummary s;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1100 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: cols == 4 ? 2.5 : 2.3,
          children: [
            _Kpi(
              label: 'Agentes en línea',
              value: '${s.agentsOnline}/${s.agentsTotal}',
              sublabel: s.agentsOffline > 0
                  ? '${s.agentsOffline} desconectados'
                  : 'Todos OK',
              icon: HugeIcons.strokeRoundedWifi01,
              color: s.agentsOffline > 0
                  ? AppColors.destructive
                  : AppColors.success,
            ),
            _Kpi(
              label: 'Jobs pendientes',
              value: '${s.jobsPending}',
              sublabel: 'En cola',
              icon: HugeIcons.strokeRoundedPrinter,
              color: s.jobsPending > 20
                  ? AppColors.warning
                  : AppColors.foreground,
            ),
            _Kpi(
              label: 'Imprimiendo ahora',
              value: '${s.jobsPrinting}',
              sublabel: 'Claimed por agente',
              icon: HugeIcons.strokeRoundedDashboardCircle,
              color: AppColors.primary,
            ),
            _Kpi(
              label: 'Fallos 1h',
              value: '${s.jobsFailed1h}',
              sublabel: '${s.jobsPrinted1h} exitosos',
              icon: HugeIcons.strokeRoundedAlert02,
              color: s.jobsFailed1h > 10
                  ? AppColors.destructive
                  : (s.jobsFailed1h > 0
                      ? AppColors.warning
                      : AppColors.success),
            ),
          ],
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.value,
    required this.sublabel,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final String sublabel;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.shadowCard,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppColors.foreground,
                  ),
                ),
                Text(
                  sublabel,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
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
// Top failures ranking
// ---------------------------------------------------------------------------

class _TopFailures extends StatelessWidget {
  const _TopFailures({required this.rows});
  final List<PrintFailureRanking> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.destructive.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  HugeIcons.strokeRoundedAlertCircle,
                  size: 14,
                  color: AppColors.destructive,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Top negocios con fallas (última hora)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < rows.length; i++)
            _RankingRow(row: rows[i], index: i + 1),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.row, required this.index});
  final PrintFailureRanking row;
  final int index;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/negocios/${row.businessId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '#$index',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.mutedForeground,
                ),
              ),
            ),
            BusinessAvatar(
              businessId: row.businessId,
              businessName: row.businessName,
              size: 30,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                row.businessName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.foreground,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (row.lastFailedAt != null)
              Text(
                formatRelative(row.lastFailedAt),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.mutedForeground,
                  fontFamily: 'monospace',
                ),
              ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.destructive.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${row.failedCount}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.destructive,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Agents grid
// ---------------------------------------------------------------------------

class _AgentsGrid extends StatelessWidget {
  const _AgentsGrid({required this.rows});
  final List<PrintAgentHealth> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.6),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.shadowCard,
        ),
        alignment: Alignment.center,
        child: const Text(
          'Sin agentes de impresión registrados.',
          style: TextStyle(color: AppColors.mutedForeground),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1200 ? 3 : (c.maxWidth >= 720 ? 2 : 1);
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: cols == 3 ? 2.2 : (cols == 2 ? 2.3 : 2.8),
          children: rows.map(_AgentCard.new).toList(),
        );
      },
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard(this.a);
  final PrintAgentHealth a;

  Color _dotColor() {
    switch (a.healthStatus) {
      case PrintAgentHealthStatus.online:
        return AppColors.success;
      case PrintAgentHealthStatus.late:
        return AppColors.warning;
      case PrintAgentHealthStatus.offline:
        return AppColors.destructive;
      case PrintAgentHealthStatus.never:
        return AppColors.mutedForeground;
    }
  }

  String _hbLabel() {
    final s = a.secondsSinceHeartbeat;
    if (s == null) return 'sin ping';
    if (s < 60) return 'hace ${s}s';
    if (s < 3600) return 'hace ${s ~/ 60}min';
    if (s < 86400) return 'hace ${s ~/ 3600}h';
    return 'hace ${s ~/ 86400}d';
  }

  @override
  Widget build(BuildContext context) {
    final color = _dotColor();
    return InkWell(
      onTap: () => context.go('/negocios/${a.businessId}'),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.6),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                BusinessAvatar(
                  businessId: a.businessId,
                  businessName: a.businessName,
                  size: 32,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        a.businessName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.foreground,
                        ),
                      ),
                      Text(
                        a.agentName ?? a.siteCode,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  a.healthStatus.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  _hbLabel(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Jobs section
// ---------------------------------------------------------------------------

class _JobsSection extends ConsumerWidget {
  const _JobsSection({required this.query, required this.jobsAsync});

  final PrintJobsQuery query;
  final AsyncValue<List<PrintJob>> jobsAsync;

  static const _filters = <({String key, String label})>[
    (key: 'non_terminal', label: 'No terminales'),
    (key: 'failed', label: 'Fallidos'),
    (key: 'pending', label: 'Pendientes'),
    (key: 'printing', label: 'Imprimiendo'),
    (key: 'cancelled', label: 'Cancelados'),
    (key: 'all', label: 'Todos'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle('Trabajos de impresión')),
            Text(
              '${jobsAsync.valueOrNull?.length ?? 0} jobs',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in _filters)
              _StatusFilterPill(
                label: f.label,
                selected: query.statusFilter == f.key,
                onTap: () => ref.read(printJobsQueryProvider.notifier).state =
                    query.copyWith(statusFilter: f.key),
              ),
          ],
        ),
        const SizedBox(height: 14),
        jobsAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error jobs: $e'),
          data: (rows) => _JobsTable(rows: rows),
        ),
      ],
    );
  }
}

class _StatusFilterPill extends StatelessWidget {
  const _StatusFilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.foreground : AppColors.muted,
          border: Border.all(
            color: selected ? AppColors.foreground : AppColors.border,
            width: 0.6,
          ),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.foreground,
          ),
        ),
      ),
    );
  }
}

class _JobsTable extends StatelessWidget {
  const _JobsTable({required this.rows});
  final List<PrintJob> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.6),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.shadowCard,
        ),
        alignment: Alignment.center,
        child: const Text(
          'Sin trabajos con este filtro. 🎉',
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _JobRow(job: rows[i]),
            if (i < rows.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _JobRow extends ConsumerWidget {
  const _JobRow({required this.job});
  final PrintJob job;

  Color get _statusColor {
    switch (job.status) {
      case PrintJobStatus.failed:
        return AppColors.destructive;
      case PrintJobStatus.printing:
        return AppColors.primary;
      case PrintJobStatus.pending:
        return AppColors.warning;
      case PrintJobStatus.printed:
        return AppColors.success;
      case PrintJobStatus.cancelled:
      case PrintJobStatus.unknown:
        return AppColors.mutedForeground;
    }
  }

  String _ageLabel() {
    final s = job.ageSeconds;
    if (s < 60) return '${s}s';
    if (s < 3600) return '${s ~/ 60}m';
    if (s < 86400) return '${s ~/ 3600}h';
    return '${s ~/ 86400}d';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _statusColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              border: Border.all(color: color.withValues(alpha: 0.25), width: 0.6),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              job.status.label.toUpperCase(),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => context.go('/negocios/${job.businessId}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          job.businessName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.foreground,
                          ),
                        ),
                      ),
                      if (job.kind != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.muted,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            job.kind!,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.mutedForeground,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                      if (job.retryCount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '×${job.retryCount}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${job.printerName ?? "—"}  ·  ${job.ip}${job.port != null ? ":${job.port}" : ""}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (job.effectiveError != null && job.effectiveError!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        job.effectiveError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.destructive,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _ageLabel(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedForeground,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  DateFormat('HH:mm', 'es_DO').format(job.createdAt),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.mutedForeground,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          if (!job.status.isTerminal) ...[
            const SizedBox(width: 4),
            _JobActions(job: job),
          ],
        ],
      ),
    );
  }
}

class _JobActions extends ConsumerWidget {
  const _JobActions({required this.job});
  final PrintJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(
        HugeIcons.strokeRoundedMoreVertical,
        size: 16,
        color: AppColors.mutedForeground,
      ),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'retry', child: Text('Reintentar')),
        PopupMenuItem(value: 'cancel', child: Text('Cancelar')),
      ],
      onSelected: (action) async {
        if (action == 'retry') {
          try {
            await ref.read(printHealthRepositoryProvider).retryJob(job.id);
            ref.invalidate(printJobsProvider);
            ref.invalidate(printHealthSummaryProvider);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Job reencolado.')),
            );
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        } else if (action == 'cancel') {
          final reason = await _askReason(context);
          if (reason == null || !context.mounted) return;
          try {
            await ref
                .read(printHealthRepositoryProvider)
                .cancelJob(job.id, reason: reason);
            ref.invalidate(printJobsProvider);
            ref.invalidate(printHealthSummaryProvider);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Job cancelado.')),
            );
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }
      },
    );
  }

  Future<String?> _askReason(BuildContext context) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar trabajo'),
        content: TextField(
          controller: ctl,
          minLines: 2,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Razón (mínimo 3 caracteres)',
            hintText: 'Ej: impresora cambiada, comanda duplicada...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.destructive),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancelar trabajo'),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    final v = ctl.text.trim();
    if (v.length < 3) return null;
    return v;
  }
}

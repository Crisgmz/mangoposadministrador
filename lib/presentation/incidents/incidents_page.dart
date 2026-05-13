import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../data/repositories/incidents_repository.dart';
import '../../domain/models/noc_incident.dart';
import '../shared/business_avatar.dart';
import '../shared/page_header.dart';

/// Centro de incidentes NOC (PRD-12 Fase 5).
///
/// - 4 KPIs (críticos, warnings, info, cerrados 24h).
/// - Botón "Escanear ahora" → corre `noc_run_auto_detection`.
/// - Filtros (estado / severidad) + lista de incidentes.
/// - Drill-down al detalle con botón "Cerrar incidente" (dialog de razón).
class IncidentsPage extends ConsumerWidget {
  const IncidentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(incidentSummaryProvider);
    final listAsync = ref.watch(incidentsListProvider);
    final query = ref.watch(incidentsQueryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'NOC',
          title: 'Incidentes',
          subtitle:
              'Eventos automáticos + abiertos manualmente. Cierra cuando resuelvas.',
          trailing: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final r = await ref
                        .read(incidentsRepositoryProvider)
                        .runAutoDetection();
                    ref.invalidate(incidentSummaryProvider);
                    ref.invalidate(incidentsListProvider);
                    ref.invalidate(activeIncidentsCountProvider);
                    ref.invalidate(criticalOpenIncidentsProvider);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Scan completo · ${r.opened} abiertos · ${r.closed} cerrados',
                        ),
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error scan: $e')),
                    );
                  }
                },
                icon: const Icon(HugeIcons.strokeRoundedSearch01, size: 14),
                label: const Text('Escanear'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref.invalidate(incidentSummaryProvider);
                  ref.invalidate(incidentsListProvider);
                  ref.invalidate(activeIncidentsCountProvider);
                  ref.invalidate(criticalOpenIncidentsProvider);
                },
                icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 14),
                label: const Text('Actualizar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        summaryAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error métricas: $e'),
          data: (s) => _KpisRow(s: s),
        ),
        const SizedBox(height: 24),
        _Filters(query: query),
        const SizedBox(height: 12),
        listAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error: $e'),
          data: (rows) => _IncidentsList(rows: rows),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

Widget _loader() => const Padding(
      padding: EdgeInsets.all(20),
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

// ---------------------------------------------------------------------------
// KPIs
// ---------------------------------------------------------------------------

class _KpisRow extends StatelessWidget {
  const _KpisRow({required this.s});
  final IncidentSummary s;

  String _oldestLabel() {
    final secs = s.oldestOpenSeconds;
    if (secs <= 0) return '—';
    if (secs < 3600) return '${secs ~/ 60}m';
    if (secs < 86400) return '${secs ~/ 3600}h';
    return '${secs ~/ 86400}d';
  }

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
          childAspectRatio: cols == 4 ? 2.6 : 2.4,
          children: [
            _Kpi(
              label: 'Críticos abiertos',
              value: '${s.openCritical}',
              sublabel: 'Requieren acción',
              icon: HugeIcons.strokeRoundedAlertCircle,
              color: s.openCritical > 0
                  ? AppColors.destructive
                  : AppColors.success,
            ),
            _Kpi(
              label: 'Atención',
              value: '${s.openWarning}',
              sublabel: 'Warnings abiertos',
              icon: HugeIcons.strokeRoundedAlert02,
              color: s.openWarning > 0
                  ? AppColors.warning
                  : AppColors.success,
            ),
            _Kpi(
              label: 'Info',
              value: '${s.openInfo}',
              sublabel: 'Total abiertos: ${s.openTotal}',
              icon: HugeIcons.strokeRoundedInformationCircle,
              color: AppColors.primary,
            ),
            _Kpi(
              label: 'Cerrados 24h',
              value: '${s.closed24h}',
              sublabel: s.oldestOpenSeconds > 0
                  ? 'Más viejo abierto: ${_oldestLabel()}'
                  : 'Sin abiertos',
              icon: HugeIcons.strokeRoundedCheckmarkCircle02,
              color: AppColors.success,
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
// Filters
// ---------------------------------------------------------------------------

class _Filters extends ConsumerWidget {
  const _Filters({required this.query});
  final IncidentsQuery query;

  static const _statuses = <({String key, String label})>[
    (key: 'open', label: 'Abiertos'),
    (key: 'closed', label: 'Cerrados'),
    (key: 'all', label: 'Todos'),
  ];

  static const _severities = <({String key, String label})>[
    (key: 'all', label: 'Toda severidad'),
    (key: 'critical', label: 'Críticos'),
    (key: 'warning', label: 'Atención'),
    (key: 'info', label: 'Info'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in _statuses)
          _Pill(
            label: s.label,
            selected: query.status == s.key,
            onTap: () =>
                ref.read(incidentsQueryProvider.notifier).state =
                    query.copyWith(status: s.key),
          ),
        Container(
          width: 1,
          height: 24,
          color: AppColors.border,
          margin: const EdgeInsets.symmetric(horizontal: 4),
        ),
        for (final s in _severities)
          _Pill(
            label: s.label,
            selected: query.severity == s.key,
            onTap: () =>
                ref.read(incidentsQueryProvider.notifier).state =
                    query.copyWith(severity: s.key),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
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

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

class _IncidentsList extends StatelessWidget {
  const _IncidentsList({required this.rows});
  final List<NocIncident> rows;

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
          'Sin incidentes con este filtro. 🎉',
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
            _IncidentRow(inc: rows[i]),
            if (i < rows.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _IncidentRow extends ConsumerWidget {
  const _IncidentRow({required this.inc});
  final NocIncident inc;

  Color get _severityColor {
    switch (inc.severity) {
      case IncidentSeverity.critical:
        return AppColors.destructive;
      case IncidentSeverity.warning:
        return AppColors.warning;
      case IncidentSeverity.info:
        return AppColors.primary;
      case IncidentSeverity.unknown:
        return AppColors.mutedForeground;
    }
  }

  String _ageLabel() {
    final s = inc.ageSeconds;
    if (s < 60) return '${s}s';
    if (s < 3600) return '${s ~/ 60}m';
    if (s < 86400) return '${s ~/ 3600}h';
    return '${s ~/ 86400}d';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _severityColor;
    final isOpen = inc.isOpen;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (inc.businessId != null && inc.businessName != null)
            BusinessAvatar(
              businessId: inc.businessId!,
              businessName: inc.businessName!,
              size: 36,
            )
          else
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.muted,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                HugeIcons.strokeRoundedAlert02,
                size: 16,
                color: AppColors.mutedForeground,
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        border: Border.all(
                            color: color.withValues(alpha: 0.25), width: 0.6),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        inc.severity.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.muted,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        inc.type,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mutedForeground,
                          fontFamily: 'monospace',
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    if (inc.source == IncidentSource.auto) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'AUTO',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      _ageLabel(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedForeground,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  inc.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
                if (inc.description != null && inc.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      inc.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Abierto ${DateFormat('dd MMM HH:mm', 'es_DO').format(inc.openedAt)}'
                  '${inc.closedAt != null ? "  ·  cerrado ${DateFormat('dd MMM HH:mm', 'es_DO').format(inc.closedAt!)}" : ""}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.mutedForeground,
                    fontFamily: 'monospace',
                  ),
                ),
                if (inc.resolutionNote != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.06),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.20),
                        width: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          HugeIcons.strokeRoundedCheckmarkCircle02,
                          size: 12,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            inc.resolutionNote!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.foreground,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isOpen) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Cerrar',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                HugeIcons.strokeRoundedCheckmarkCircle02,
                size: 18,
                color: AppColors.success,
              ),
              onPressed: () => _closeIncident(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _closeIncident(BuildContext context, WidgetRef ref) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar incidente'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                inc.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
              if (inc.businessName != null) ...[
                const SizedBox(height: 2),
                Text(
                  inc.businessName!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: ctl,
                minLines: 2,
                maxLines: 5,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nota de resolución (mínimo 3 caracteres)',
                  hintText:
                      'Ej: cliente llamó, reinicio del agente, NCF corregido...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar incidente'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final note = ctl.text.trim();
    if (note.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nota requerida (3+ caracteres).')),
      );
      return;
    }
    try {
      await ref
          .read(incidentsRepositoryProvider)
          .closeIncident(inc.id, note: note);
      ref.invalidate(incidentSummaryProvider);
      ref.invalidate(incidentsListProvider);
      ref.invalidate(activeIncidentsCountProvider);
      ref.invalidate(criticalOpenIncidentsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incidente cerrado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}


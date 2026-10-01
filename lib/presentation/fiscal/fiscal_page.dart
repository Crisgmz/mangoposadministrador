import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/ecf_onboarding_repository.dart';
import '../../data/repositories/fiscal_health_repository.dart';
import '../../domain/models/fiscal_health.dart';
import '../shared/business_avatar.dart';
import '../shared/page_header.dart';
import 'ecf_requests_section.dart';
import '../../data/repositories/external_ecf_requests_repository.dart';
import 'external_ecf_requests_section.dart';

/// NOC Fiscal (PRD-12 Fase 3): e-CFs stuck/rechazados y secuencias NCF
/// próximas a agotarse o vencer.
class FiscalPage extends ConsumerWidget {
  const FiscalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(fiscalHealthSummaryProvider);
    final problemsAsync = ref.watch(fiscalProblemsProvider);
    final sequencesAsync = ref.watch(ncfSequencesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          kicker: 'Fiscal',
          title: 'Salud fiscal',
          subtitle: 'Estado de e-CFs y secuencias NCF cross-tenant.',
          trailing: OutlinedButton.icon(
            onPressed: () {
              ref.invalidate(ecfRequestsProvider);
              ref.invalidate(externalEcfRequestsProvider);
              ref.invalidate(fiscalHealthSummaryProvider);
              ref.invalidate(fiscalProblemsProvider);
              ref.invalidate(ncfSequencesProvider);
            },
            icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
            label: const Text('Actualizar'),
          ),
        ),
        const SizedBox(height: 24),
        const EcfRequestsSection(),
        const ExternalEcfRequestsSection(),
        summaryAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error métricas: $e'),
          data: (s) => _KpisGrid(s: s),
        ),
        const SizedBox(height: 28),
        const _SectionTitle('Documentos con problemas'),
        const SizedBox(height: 10),
        const _ProblemsFilters(),
        const SizedBox(height: 12),
        problemsAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error: $e'),
          data: (rows) => _ProblemsList(rows: rows),
        ),
        const SizedBox(height: 28),
        const _SectionTitle('Secuencias NCF'),
        const SizedBox(height: 10),
        const _SequencesFilters(),
        const SizedBox(height: 12),
        sequencesAsync.when(
          loading: _loader,
          error: (e, _) => _err('Error: $e'),
          data: (rows) => _SequencesList(rows: rows),
        ),
        const SizedBox(height: 18),
        const _PolicyHint(),
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
// KPIs grid
// ---------------------------------------------------------------------------

class _KpisGrid extends StatelessWidget {
  const _KpisGrid({required this.s});
  final FiscalHealthSummary s;

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
              label: 'e-CFs stuck',
              value: '${s.ecfStuck}',
              sublabel: '>1h sin ACK',
              icon: HugeIcons.strokeRoundedClock04,
              color: s.ecfStuck > 0 ? AppColors.warning : AppColors.success,
            ),
            _Kpi(
              label: 'Rechazados 24h',
              value: '${s.ecfRejected24h}',
              sublabel: 'DGII',
              icon: HugeIcons.strokeRoundedAlertCircle,
              color: s.ecfRejected24h > 0
                  ? AppColors.destructive
                  : AppColors.success,
            ),
            _Kpi(
              label: 'NCF críticas',
              value: '${s.ncfCritical}',
              sublabel: '<50 disponibles',
              icon: HugeIcons.strokeRoundedInvoice03,
              color: s.ncfCritical > 0
                  ? AppColors.destructive
                  : AppColors.success,
            ),
            _Kpi(
              label: 'NCF por vencer',
              value: '${s.ncfExpiring + s.ncfExpired}',
              sublabel: s.ncfExpired > 0
                  ? '${s.ncfExpired} vencidas'
                  : '< 15 días',
              icon: HugeIcons.strokeRoundedCalendar03,
              color: s.ncfExpired > 0
                  ? AppColors.destructive
                  : (s.ncfExpiring > 0
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
// Filters (pill toggles)
// ---------------------------------------------------------------------------

class _ProblemsFilters extends ConsumerWidget {
  const _ProblemsFilters();

  static const _filters = <({String key, String label})>[
    (key: 'all', label: 'Todos'),
    (key: 'rejected', label: 'Rechazados'),
    (key: 'stuck', label: 'Stuck'),
    (key: 'cancelled', label: 'Anulados'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(fiscalProblemsQueryProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in _filters)
          _Pill(
            label: f.label,
            selected: q.kind == f.key,
            onTap: () => ref.read(fiscalProblemsQueryProvider.notifier).state =
                q.copyWith(kind: f.key),
          ),
      ],
    );
  }
}

class _SequencesFilters extends ConsumerWidget {
  const _SequencesFilters();

  static const _filters = <({String key, String label})>[
    (key: 'all', label: 'Todas'),
    (key: 'critical', label: 'Críticas'),
    (key: 'warning', label: 'Bajas'),
    (key: 'expiring', label: 'Por vencer'),
    (key: 'expired', label: 'Vencidas'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(ncfSequencesQueryProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in _filters)
          _Pill(
            label: f.label,
            selected: q.statusFilter == f.key,
            onTap: () => ref.read(ncfSequencesQueryProvider.notifier).state =
                q.copyWith(statusFilter: f.key),
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
// Problems list (responsive)
// ---------------------------------------------------------------------------

class _ProblemsList extends StatelessWidget {
  const _ProblemsList({required this.rows});
  final List<FiscalProblem> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return _emptyCard('Sin documentos con problemas. 🎉');
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
            _ProblemRow(p: rows[i]),
            if (i < rows.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _ProblemRow extends ConsumerWidget {
  const _ProblemRow({required this.p});
  final FiscalProblem p;

  Color get _color {
    switch (p.problemKind) {
      case FiscalProblemKind.rejected:
        return AppColors.destructive;
      case FiscalProblemKind.stuck:
        return AppColors.warning;
      case FiscalProblemKind.cancelled:
        return AppColors.mutedForeground;
      case FiscalProblemKind.ok:
        return AppColors.success;
    }
  }

  String _ageLabel() {
    final s = p.ageSeconds;
    if (s < 60) return '${s}s';
    if (s < 3600) return '${s ~/ 60}m';
    if (s < 86400) return '${s ~/ 3600}h';
    return '${s ~/ 86400}d';
  }

  bool get _isRetryable =>
      p.problemKind == FiscalProblemKind.rejected ||
      p.problemKind == FiscalProblemKind.stuck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BusinessAvatar(
            businessId: p.businessId,
            businessName: p.businessName,
            size: 36,
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
                        p.problemKind.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.businessName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
                    if (_isRetryable) ...[
                      const SizedBox(width: 4),
                      _RetryButton(p: p),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${p.ncfType}  ·  ${p.ncfNumber}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.mutedForeground,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${p.customerName}  ·  ${formatRd(p.total)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.foreground,
                  ),
                ),
                if (p.cancellationReason != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    p.cancellationReason!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  'Emitido ${DateFormat('dd MMM HH:mm', 'es_DO').format(p.issuedAt)}  ·  hace ${_ageLabel()}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.mutedForeground,
                    fontFamily: 'monospace',
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

class _RetryButton extends ConsumerWidget {
  const _RetryButton({required this.p});
  final FiscalProblem p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: 'Marcar para reintento',
      icon: const Icon(
        HugeIcons.strokeRoundedRefresh,
        size: 16,
        color: AppColors.primary,
      ),
      onPressed: () async {
        final reason = await _askReason(context);
        if (reason == null || !context.mounted) return;
        try {
          await ref
              .read(fiscalHealthRepositoryProvider)
              .markEcfForRetry(p.id, reason: reason);
          ref.invalidate(fiscalProblemsProvider);
          ref.invalidate(fiscalHealthSummaryProvider);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${p.ncfNumber} marcado para reintento.')),
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      },
    );
  }

  Future<String?> _askReason(BuildContext context) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar e-CF para reintento'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'NCF: ${p.ncfNumber}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctl,
                minLines: 2,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Razón (mínimo 3 caracteres)',
                  hintText: 'Ej: error de NCF duplicado corregido en DGII',
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
            child: const Text('Marcar para reintento'),
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

// ---------------------------------------------------------------------------
// NCF sequences list (responsive)
// ---------------------------------------------------------------------------

class _SequencesList extends StatelessWidget {
  const _SequencesList({required this.rows});
  final List<NcfSequenceStatus> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return _emptyCard('Sin secuencias que coincidan con el filtro.');
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
            _SequenceRow(s: rows[i]),
            if (i < rows.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _SequenceRow extends StatelessWidget {
  const _SequenceRow({required this.s});
  final NcfSequenceStatus s;

  Color get _color {
    switch (s.healthStatus) {
      case NcfHealthStatus.critical:
      case NcfHealthStatus.expired:
        return AppColors.destructive;
      case NcfHealthStatus.warning:
      case NcfHealthStatus.expiringSoon:
        return AppColors.warning;
      case NcfHealthStatus.inactive:
        return AppColors.mutedForeground;
      case NcfHealthStatus.ok:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BusinessAvatar(
            businessId: s.businessId,
            businessName: s.businessName,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.businessName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
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
                        s.healthStatus.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.ncfType}  ·  ${s.prefix}${s.serie}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.mutedForeground,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 6),
                // Línea de disponibilidad + barra
                Row(
                  children: [
                    Text(
                      '${formatInt(s.available)} disp.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'de ${formatInt(s.rangeEnd - s.rangeStart + 1)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    if (s.expirationDate != null) ...[
                      const Spacer(),
                      const Icon(
                        HugeIcons.strokeRoundedCalendar03,
                        size: 12,
                        color: AppColors.mutedForeground,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM/yy', 'es_DO')
                            .format(s.expirationDate!),
                        style: TextStyle(
                          fontSize: 11,
                          color: s.healthStatus == NcfHealthStatus.expired
                              ? AppColors.destructive
                              : AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: s.consumedRatio,
                    minHeight: 4,
                    backgroundColor: AppColors.muted,
                    valueColor: AlwaysStoppedAnimation(color),
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
// Helpers
// ---------------------------------------------------------------------------

Widget _emptyCard(String text) => Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      alignment: Alignment.center,
      child: Text(text,
          style: const TextStyle(color: AppColors.mutedForeground)),
    );

class _PolicyHint extends StatelessWidget {
  const _PolicyHint();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            HugeIcons.strokeRoundedInformationCircle,
            size: 16,
            color: AppColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.foreground,
                  height: 1.45,
                ),
                children: [
                  TextSpan(
                    text: 'Umbrales: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: 'NCF '),
                  TextSpan(
                    text: 'crítica < 50',
                    style: TextStyle(
                      color: AppColors.destructive,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' · '),
                  TextSpan(
                    text: 'baja < 200',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' · expira pronto < 15 días.\n'),
                  TextSpan(
                    text: 'e-CF stuck: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                      text:
                          'pendiente o enviado a DGII hace > 1 hora sin ACK. '
                          'Reintentar marca el documento de vuelta a pending '
                          'para que el worker Alanube lo procese otra vez.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

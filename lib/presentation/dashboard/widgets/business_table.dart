import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/format/formatters.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../domain/models/business_overview.dart';
import '../../shared/business_avatar.dart';
import 'status_badges.dart';

class BusinessTable extends ConsumerWidget {
  const BusinessTable({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(filteredOverviewProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: dataAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(40),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Error cargando negocios: $e',
            style: const TextStyle(color: AppColors.destructive, fontSize: 13),
          ),
        ),
        data: (rows) => _Body(rows: rows),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.rows});
  final List<BusinessOverview> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Negocios activos',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground,
                      ),
                    ),
                    SizedBox(height: 2),
                  ],
                ),
              ),
              Text(
                '${rows.length} ${rows.length == 1 ? "negocio" : "negocios"}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AppColors.border),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Aún no hay negocios registrados.',
                style: TextStyle(color: AppColors.mutedForeground),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              // Mobile/tablet estrecho: cards apiladas, sin scroll horizontal.
              if (constraints.maxWidth < 760) {
                return _MobileList(rows: rows);
              }
              // Desktop: tabla. Si el ancho no llega a 1000 px (raro pero
              // pasa con sidebar más ancho), hacemos scroll horizontal.
              final tableWidth = constraints.maxWidth >= 1000
                  ? constraints.maxWidth
                  : 1000.0;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: _Table(rows: rows),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Lista en cards para anchos mobile (< 760 px) — evita el scroll horizontal.
class _MobileList extends StatelessWidget {
  const _MobileList({required this.rows});
  final List<BusinessOverview> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _MobileCard(b: rows[i]),
          if (i < rows.length - 1)
            const Divider(height: 1, thickness: 1, color: AppColors.border),
        ],
      ],
    );
  }
}

class _MobileCard extends StatelessWidget {
  const _MobileCard({required this.b});
  final BusinessOverview b;

  Color get _failColor {
    if (b.printFailures24h == 0) return AppColors.mutedForeground;
    if (b.printFailures24h > 20) return AppColors.destructive;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/negocios/${b.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            BusinessAvatar(
              businessId: b.id,
              businessName: b.name,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          b.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: b.isInactive
                                ? AppColors.mutedForeground
                                : AppColors.foreground,
                            decoration: b.isInactive
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _StatusInline(business: b),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${b.businessType ?? "—"} · ${b.domain}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PlanBadge(plan: b.plan),
                      NcfBadge(status: b.ncfStatus),
                      AgentBadge(status: b.agentStatus),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Línea de métricas — siempre visible sin swipe.
                  DefaultTextStyle.merge(
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.foreground,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text.rich(
                          TextSpan(children: [
                            const TextSpan(
                              text: 'Hoy: ',
                              style: TextStyle(
                                color: AppColors.mutedForeground,
                                fontSize: 11,
                              ),
                            ),
                            TextSpan(
                              text: formatRd(b.revenueToday),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: '  ·  ${formatInt(b.salesToday)} vtas',
                              style: const TextStyle(
                                color: AppColors.mutedForeground,
                                fontSize: 11,
                              ),
                            ),
                          ]),
                        ),
                        if (b.printJobsToday > 0)
                          Text.rich(
                            TextSpan(children: [
                              const TextSpan(
                                text: 'Impr: ',
                                style: TextStyle(
                                  color: AppColors.mutedForeground,
                                  fontSize: 11,
                                ),
                              ),
                              TextSpan(
                                text: '${b.printFailures24h}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _failColor,
                                ),
                              ),
                              TextSpan(
                                text: '/${b.printJobsToday} fallas',
                                style: const TextStyle(
                                  color: AppColors.mutedForeground,
                                  fontSize: 11,
                                ),
                              ),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
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

class _Table extends StatelessWidget {
  const _Table({required this.rows});
  final List<BusinessOverview> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _TableHeader(),
        const Divider(height: 1, thickness: 1, color: AppColors.border),
        for (var i = 0; i < rows.length; i++) ...[
          _TableRow(b: rows[i]),
          if (i < rows.length - 1)
            const Divider(height: 1, thickness: 1, color: AppColors.border),
        ],
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.muted.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: const Row(
        children: [
          Expanded(flex: 3, child: _HeaderCell('Negocio', textAlign: TextAlign.left)),
          Expanded(flex: 1, child: _HeaderCell('Plan', textAlign: TextAlign.left)),
          Expanded(flex: 1, child: _HeaderCell('Ventas', textAlign: TextAlign.right)),
          Expanded(flex: 2, child: _HeaderCell('Ingresos hoy', textAlign: TextAlign.right)),
          Expanded(flex: 1, child: _HeaderCell('NCF', textAlign: TextAlign.center)),
          Expanded(flex: 2, child: _HeaderCell('Agente', textAlign: TextAlign.center)),
          Expanded(flex: 1, child: _HeaderCell('Impr. fallas', textAlign: TextAlign.right)),
          SizedBox(width: 28),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {required this.textAlign});
  final String text;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      textAlign: textAlign,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.mutedForeground,
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.b});
  final BusinessOverview b;

  Color _printFailColor() {
    if (b.printFailures24h == 0) return AppColors.mutedForeground;
    if (b.printFailures24h > 20) return AppColors.destructive;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/negocios/${b.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  BusinessAvatar(
                    businessId: b.id,
                    businessName: b.name,
                    size: 38,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                b.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: b.isInactive
                                      ? AppColors.mutedForeground
                                      : AppColors.foreground,
                                  decoration: b.isInactive
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusInline(business: b),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${b.businessType ?? "—"} · ${b.domain}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.mutedForeground,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: PlanBadge(plan: b.plan),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                formatInt(b.salesToday),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: AppColors.foreground,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                formatRd(b.revenueToday),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: AppColors.foreground,
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  NcfBadge(status: b.ncfStatus),
                  const SizedBox(height: 4),
                  Text(
                    '${formatInt(b.ncfAvailable)} disp.',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.mutedForeground,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  AgentBadge(status: b.agentStatus),
                  const SizedBox(height: 4),
                  Text(
                    formatRelative(b.agentLastSeen),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.mutedForeground,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${b.printFailures24h}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: _printFailColor(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '/ ${b.printJobsToday}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(
              width: 28,
              child: Icon(
                HugeIcons.strokeRoundedArrowRight01,
                size: 16,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Badge inline al lado del nombre del negocio. Renderiza:
///   * `PENDING` (naranja) si `status='pending'`
///   * `INACTIVO` (rojo) si `status='inactive'`
///   * Nada si `active` (el caso común, no metemos ruido visual).
class _StatusInline extends StatelessWidget {
  const _StatusInline({required this.business});

  final BusinessOverview business;

  @override
  Widget build(BuildContext context) {
    if (business.isActive) return const SizedBox.shrink();
    final (color, label) = business.isPending
        ? (AppColors.accent, 'PENDING')
        : (AppColors.destructive, 'INACTIVO');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: color,
        ),
      ),
    );
  }
}

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

/// Tabla de negocios ordenada por riesgo operativo.
///
/// La misma tabla sirve a Vista Global (recortada a las primeras filas, con
/// enlace al listado completo) y a la página de Negocios (completa). Lo que
/// cambia entre las dos es cuántas filas se muestran, no cómo se leen.
class BusinessTable extends ConsumerWidget {
  const BusinessTable({
    super.key,
    this.maxRows,
    this.title = 'Negocios',
    this.showToolbar = true,
    this.onSeeAll,
  });

  /// Corta el listado. `null` = todas las filas.
  final int? maxRows;
  final String title;

  /// Segmentos + buscador. La página de Negocios ya trae su propio filtro de
  /// status arriba, pero igual quiere estos.
  final bool showToolbar;

  /// Qué hacer con "Ver todos los negocios". Si es `null` y hay filas
  /// ocultas, se navega a `/negocios`.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(riskSortedOverviewProvider);

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
        data: (rows) => _Body(
          rows: rows,
          maxRows: maxRows,
          title: title,
          showToolbar: showToolbar,
          onSeeAll: onSeeAll,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.rows,
    required this.maxRows,
    required this.title,
    required this.showToolbar,
    required this.onSeeAll,
  });

  final List<BusinessOverview> rows;
  final int? maxRows;
  final String title;
  final bool showToolbar;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final limit = maxRows;
    final visible = (limit != null && rows.length > limit)
        ? rows.take(limit).toList(growable: false)
        : rows;
    final hidden = rows.length - visible.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(title: title, total: rows.length, showFilters: showToolbar),
        const Divider(height: 1, thickness: 1, color: AppColors.border),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Ningún negocio coincide con el filtro.',
                style: TextStyle(color: AppColors.mutedForeground),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              // Mobile/tablet estrecho: cards apiladas, sin scroll horizontal.
              if (constraints.maxWidth < 760) {
                return _MobileList(rows: visible);
              }
              final tableWidth = constraints.maxWidth >= 1040
                  ? constraints.maxWidth
                  : 1040.0;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: _Table(rows: visible),
                ),
              );
            },
          ),
        if (hidden > 0)
          _Footer(
            shown: visible.length,
            total: rows.length,
            onSeeAll: onSeeAll ?? () => context.go('/negocios'),
          ),
      ],
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.title,
    required this.total,
    required this.showFilters,
  });

  final String title;
  final int total;
  final bool showFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.foreground,
          ),
        ),
        Text(
          '$total ${total == 1 ? "negocio" : "negocios"} · ordenados por '
          'riesgo operativo',
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.mutedForeground,
          ),
        ),
      ],
    );

    if (!showFilters) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: heading,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tight = constraints.maxWidth < 780;
          final controls = [
            const _SegmentChips(),
            const SizedBox(width: 10),
            const _TableSearchField(),
          ];

          if (tight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 12),
                const _SegmentChips(),
                const SizedBox(height: 10),
                const _TableSearchField(expand: true),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: heading),
              ...controls,
            ],
          );
        },
      ),
    );
  }
}

class _SegmentChips extends ConsumerWidget {
  const _SegmentChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(businessActivityFilterProvider);
    // Los conteos salen del listado SIN el filtro de segmento — si no, al
    // elegir "Caídos" los otros chips mostrarían cero.
    final all = ref.watch(filteredOverviewProvider).valueOrNull ?? const [];

    int countOf(BusinessActivitySegment? s) => s == null
        ? all.length
        : all.where((b) => businessSegmentOf(b) == s).length;

    void select(BusinessActivitySegment? s) =>
        ref.read(businessActivityFilterProvider.notifier).state = s;

    const labels = <BusinessActivitySegment, String>{
      BusinessActivitySegment.down: 'Caídos',
      BusinessActivitySegment.late: 'Tardíos',
      BusinessActivitySegment.online: 'En línea',
    };
    const colors = <BusinessActivitySegment, Color>{
      BusinessActivitySegment.down: AppColors.destructive,
      BusinessActivitySegment.late: AppColors.warning,
      BusinessActivitySegment.online: AppColors.primary,
    };

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _SegmentChip(
          label: 'Todos · ${countOf(null)}',
          active: active == null,
          color: AppColors.mutedForeground,
          onTap: () => select(null),
        ),
        for (final s in labels.keys)
          _SegmentChip(
            label: '${labels[s]} · ${countOf(s)}',
            active: active == s,
            color: colors[s]!,
            onTap: () => select(active == s ? null : s),
          ),
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.foreground : AppColors.muted,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Filtro de la tabla. Escribe en el MISMO estado que el buscador del topbar,
/// así que buscar arriba deja la tabla filtrada y viceversa.
class _TableSearchField extends ConsumerStatefulWidget {
  const _TableSearchField({this.expand = false});
  final bool expand;

  @override
  ConsumerState<_TableSearchField> createState() => _TableSearchFieldState();
}

class _TableSearchFieldState extends ConsumerState<_TableSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(businessSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Si el query cambia desde afuera (topbar), el campo lo refleja.
    ref.listen<String>(businessSearchQueryProvider, (_, next) {
      if (_controller.text != next) _controller.text = next;
    });

    final field = SizedBox(
      height: 34,
      child: TextField(
        controller: _controller,
        onChanged: (v) =>
            ref.read(businessSearchQueryProvider.notifier).state = v,
        style: const TextStyle(fontSize: 12.5),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Filtrar negocios…',
          hintStyle: const TextStyle(
            fontSize: 12.5,
            color: AppColors.mutedForeground,
          ),
          prefixIcon: const Icon(HugeIcons.strokeRoundedSearch01, size: 15),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar',
                  iconSize: 14,
                  splashRadius: 13,
                  icon: const Icon(HugeIcons.strokeRoundedCancel01),
                  onPressed: () {
                    _controller.clear();
                    ref.read(businessSearchQueryProvider.notifier).state = '';
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );

    return widget.expand ? field : SizedBox(width: 210, child: field);
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.shown,
    required this.total,
    required this.onSeeAll,
  });

  final int shown;
  final int total;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.muted.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Mostrando $shown de $total',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.mutedForeground,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: onSeeAll,
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.card,
              foregroundColor: AppColors.foreground,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Ver todos los negocios'),
          ),
        ],
      ),
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
    final risky = businessIsAtRisk(b);
    return Material(
      color: risky
          ? AppColors.destructive.withValues(alpha: 0.03)
          : AppColors.card,
      child: InkWell(
        onTap: () => context.go('/negocios/${b.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BusinessAvatar(businessId: b.id, businessName: b.name, size: 40),
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
                        _HeartbeatDot(status: b.agentStatus),
                        const SizedBox(width: 6),
                        _StatusInline(business: b),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'latido ${_heartbeatLabel(b)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        fontWeight: risky ? FontWeight.w700 : FontWeight.w400,
                        color: risky
                            ? AppColors.destructive
                            : AppColors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        PlanBadge(plan: b.plan),
                        NcfBadge(status: b.ncfStatus),
                      ],
                    ),
                    const SizedBox(height: 7),
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
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Hoy ',
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
                                  text: ' · ${formatInt(b.salesToday)} vtas',
                                  style: const TextStyle(
                                    color: AppColors.mutedForeground,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (b.printJobsToday > 0)
                            Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(
                                    text: 'Impr ',
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
                                ],
                              ),
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
      ),
    );
  }
}

/// Proporciones de la grilla. Están acá arriba porque encabezado y filas
/// TIENEN que compartirlas — si divergen, las columnas dejan de alinearse.
const _kFlexName = 27;
const _kFlexHeartbeat = 14;
const _kFlexPlan = 10;
const _kFlexSales = 10;
const _kFlexRevenue = 14;
const _kFlexNcf = 11;
const _kFlexFails = 11;
const _kChevron = 28.0;

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
          Expanded(flex: _kFlexName, child: _HeaderCell('Negocio')),
          Expanded(flex: _kFlexHeartbeat, child: _HeaderCell('Últ. latido')),
          Expanded(flex: _kFlexPlan, child: _HeaderCell('Plan')),
          Expanded(
            flex: _kFlexSales,
            child: _HeaderCell('Ventas', textAlign: TextAlign.right),
          ),
          Expanded(
            flex: _kFlexRevenue,
            child: _HeaderCell('Ingresos hoy', textAlign: TextAlign.right),
          ),
          Expanded(
            flex: _kFlexNcf,
            child: _HeaderCell('NCF', textAlign: TextAlign.center),
          ),
          Expanded(
            flex: _kFlexFails,
            child: _HeaderCell('Impr. fallas', textAlign: TextAlign.right),
          ),
          SizedBox(width: _kChevron),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {this.textAlign = TextAlign.left});
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

/// Punto de latido. El verde lleva halo para que "en línea" se lea de un
/// vistazo en una columna llena de puntos.
class _HeartbeatDot extends StatelessWidget {
  const _HeartbeatDot({required this.status});
  final AgentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AgentStatus.online => AppColors.primary,
      AgentStatus.late => AppColors.warning,
      AgentStatus.offline => AppColors.destructive,
      AgentStatus.none => AppColors.mutedForeground,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: status == AgentStatus.online
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
    );
  }
}

String _heartbeatLabel(BusinessOverview b) =>
    b.agentStatus == AgentStatus.none ? '—' : formatRelative(b.agentLastSeen);

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
    final risky = businessIsAtRisk(b);

    return Material(
      // Tinte rojísimo (3%) en la fila: marca el bloque de riesgo sin gritar,
      // y funciona junto al punto de latido en vez de competir con él.
      color: risky
          ? AppColors.destructive.withValues(alpha: 0.03)
          : AppColors.card,
      child: InkWell(
        onTap: () => context.go('/negocios/${b.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Expanded(
                flex: _kFlexName,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    children: [
                      BusinessAvatar(
                        businessId: b.id,
                        businessName: b.name,
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
                              b.domain.isEmpty
                                  ? (b.businessType ?? '—')
                                  : b.domain,
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
              ),
              Expanded(
                flex: _kFlexHeartbeat,
                child: Row(
                  children: [
                    _HeartbeatDot(status: b.agentStatus),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        _heartbeatLabel(b),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          fontWeight: risky ? FontWeight.w700 : FontWeight.w400,
                          color: risky
                              ? AppColors.destructive
                              : AppColors.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: _kFlexPlan,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PlanBadge(plan: b.plan),
                ),
              ),
              Expanded(
                flex: _kFlexSales,
                child: Text(
                  formatInt(b.salesToday),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: AppColors.foreground,
                  ),
                ),
              ),
              Expanded(
                flex: _kFlexRevenue,
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
                flex: _kFlexNcf,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NcfBadge(status: b.ncfStatus),
                    const SizedBox(height: 3),
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
                flex: _kFlexFails,
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
                width: _kChevron,
                child: Icon(
                  HugeIcons.strokeRoundedArrowRight01,
                  size: 16,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
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

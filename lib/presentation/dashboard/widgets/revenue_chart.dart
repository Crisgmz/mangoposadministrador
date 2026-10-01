import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/format/formatters.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../../../domain/models/revenue_hour.dart';

class RevenueChart extends ConsumerWidget {
  const RevenueChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(revenueTrend12hProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      child: dataAsync.when(
        loading: () => const SizedBox(
          height: 260,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (e, _) => const SizedBox(
          height: 260,
          child: Center(
            child: Text(
              'Error cargando ingresos',
              style: TextStyle(color: AppColors.destructive),
            ),
          ),
        ),
        data: _Chart.new,
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart(this.points);
  final List<RevenueHour> points;

  /// Hay comparación solo si el backend la devolvió (migración 0041 aplicada)
  /// y además ayer hubo movimiento. Una línea plana en cero no compara nada:
  /// se leería como "ayer no se vendió" cuando en realidad no hay dato.
  bool get _hasComparison =>
      points.any((p) => p.revenuePrev != null) &&
      points.fold<double>(0, (s, p) => s + (p.revenuePrev ?? 0)) > 0;

  @override
  Widget build(BuildContext context) {
    final total = points.fold<double>(0, (s, p) => s + p.revenue);
    final totalTx = points.fold<int>(0, (s, p) => s + p.transactions);
    final totalPrev = points.fold<double>(
      0,
      (s, p) => s + (p.revenuePrev ?? 0),
    );

    // Escala compartida por las dos series: si cada una usara su propio
    // máximo, la comparación visual sería mentira.
    final maxY = points.isEmpty
        ? 1.0
        : points
              .map(
                (p) => _hasComparison
                    ? (p.revenue > (p.revenuePrev ?? 0)
                          ? p.revenue
                          : p.revenuePrev!)
                    : p.revenue,
              )
              .reduce((a, b) => a > b ? a : b);

    final deltaPct = (_hasComparison && totalPrev > 0)
        ? ((total - totalPrev) / totalPrev) * 100
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          total: total,
          totalTx: totalTx,
          deltaPct: deltaPct,
          showLegend: _hasComparison,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: points.isEmpty
              ? const _EmptyChart()
              : LineChart(_buildChart(points, maxY)),
        ),
      ],
    );
  }

  LineChartData _buildChart(List<RevenueHour> data, double maxY) {
    List<FlSpot> spotsOf(double Function(RevenueHour) pick) => [
      for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), pick(data[i])),
    ];

    return LineChartData(
      minX: 0,
      maxX: (data.length - 1).toDouble(),
      minY: 0,
      maxY: maxY <= 0 ? 1 : maxY * 1.15,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY <= 0 ? 1 : (maxY / 4),
        getDrawingHorizontalLine: (_) => const FlLine(
          color: AppColors.border,
          strokeWidth: 1,
          dashArray: [4, 4],
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            interval: maxY <= 0 ? 1 : (maxY / 4),
            getTitlesWidget: (v, _) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                v >= 1000
                    ? '${(v / 1000).toStringAsFixed(0)}k'
                    : v.toStringAsFixed(0),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.mutedForeground,
                ),
              ),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: 2,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= data.length) return const SizedBox.shrink();
              return Text(
                data[i].label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.mutedForeground,
                ),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppColors.foreground,
          tooltipRoundedRadius: 8,
          tooltipPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          getTooltipItems: (touched) => touched.map((spot) {
            final p = data[spot.x.toInt()];
            // El tooltip solo lo emite la serie de hoy: dos globos superpuestos
            // en el mismo punto tapaban el gráfico.
            if (spot.barIndex != 0) return null;
            final ayer = _hasComparison && p.revenuePrev != null
                ? '\nayer ${formatRd(p.revenuePrev!)}'
                : '';
            return LineTooltipItem(
              '${p.label}\n${formatRd(p.revenue)}$ayer',
              const TextStyle(
                color: AppColors.background,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spotsOf((p) => p.revenue),
          isCurved: true,
          curveSmoothness: 0.32,
          color: AppColors.primary,
          barWidth: 2.5,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primary.withValues(alpha: 0.30),
                AppColors.primary.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        if (_hasComparison)
          LineChartBarData(
            spots: spotsOf((p) => p.revenuePrev ?? 0),
            isCurved: true,
            curveSmoothness: 0.32,
            color: AppColors.mutedForeground.withValues(alpha: 0.45),
            barWidth: 1.5,
            isStrokeCapRound: true,
            dashArray: const [5, 5],
            dotData: const FlDotData(show: false),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.totalTx,
    required this.deltaPct,
    required this.showLegend,
  });

  final double total;
  final int totalTx;
  final double? deltaPct;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 560;

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ingresos últimas 12 horas',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              showLegend
                  ? 'Plataforma completa · comparado con ayer a la misma hora'
                  : 'Plataforma completa · todos los negocios',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        );

        final totals = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'TOTAL',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedForeground,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatRd(total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  ),
                ),
                if (deltaPct != null) ...[
                  const SizedBox(width: 6),
                  _Delta(pct: deltaPct!),
                ],
              ],
            ),
            Text(
              '${formatInt(totalTx)} transacciones',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        );

        if (tight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: totals),
              if (showLegend) ...[const SizedBox(height: 8), const _Legend()],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            if (showLegend) ...[
              const _Legend(),
              const SizedBox(width: 14),
              Container(width: 1, height: 32, color: AppColors.border),
              const SizedBox(width: 14),
            ],
            totals,
          ],
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendItem(color: AppColors.primary, label: 'Hoy', dashed: false),
        const SizedBox(width: 12),
        _LegendItem(
          color: AppColors.mutedForeground.withValues(alpha: 0.5),
          label: 'Ayer',
          dashed: true,
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.dashed,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 2,
          child: dashed
              ? Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(child: ColoredBox(color: color)),
                    ],
                  ],
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta({required this.pct});
  final double pct;

  @override
  Widget build(BuildContext context) {
    final up = pct >= 0;
    final color = up ? AppColors.primary : AppColors.destructive;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up
                ? HugeIcons.strokeRoundedArrowUp01
                : HugeIcons.strokeRoundedArrowDown01,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            '${pct.abs().toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Sin ventas registradas en las últimas 12 horas',
        style: TextStyle(color: AppColors.mutedForeground, fontSize: 13),
      ),
    );
  }
}

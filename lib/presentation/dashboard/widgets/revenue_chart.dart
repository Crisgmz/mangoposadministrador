import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        error: (e, _) => SizedBox(
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

  @override
  Widget build(BuildContext context) {
    final total = points.fold<double>(0, (s, p) => s + p.revenue);
    final totalTx = points.fold<int>(0, (s, p) => s + p.transactions);
    final maxY = points.isEmpty
        ? 1.0
        : points.map((p) => p.revenue).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(total: total, totalTx: totalTx),
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
    final spots = <FlSpot>[
      for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].revenue),
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
        getDrawingHorizontalLine: (_) => FlLine(
          color: AppColors.border,
          strokeWidth: 1,
          dashArray: const [4, 4],
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            interval: maxY <= 0 ? 1 : (maxY / 4),
            getTitlesWidget: (v, _) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
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
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          getTooltipItems: (touched) => touched.map((spot) {
            final p = data[spot.x.toInt()];
            return LineTooltipItem(
              '${p.label}\n${formatRd(p.revenue)}',
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
          spots: spots,
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
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.total, required this.totalTx});
  final double total;
  final int totalTx;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ingresos últimas 12 horas',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.foreground,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Plataforma completa · todos los negocios',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
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
            Text(
              formatRd(total),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
              ),
            ),
            Text(
              '$totalTx transacciones',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ],
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

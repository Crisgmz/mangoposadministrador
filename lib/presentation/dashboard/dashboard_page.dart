import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/breakpoints.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../domain/models/business_overview.dart';
import '../incidents/widgets/critical_incidents_banner.dart';
import 'widgets/alerts_panel.dart';
import 'widgets/business_table.dart';
import 'widgets/metric_card.dart';
import 'widgets/operating_now_sheet.dart';
import 'widgets/revenue_chart.dart';

/// Vista global — pantalla principal de la consola operadora.
///
/// Lee `get_platform_overview`, `get_revenue_trend_12h` y `get_platform_alerts`
/// vía sus providers en `dashboard_repository.dart`. Refresh manual con el
/// botón del header (invalida los tres providers).
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(filteredOverviewProvider);
    final isWide = Breakpoints.isDesktop(context);

    // El scroll vertical lo provee `AppShell._ContentArea`. Aquí solo
    // emitimos la columna de contenido — anidar otro SingleChildScrollView
    // bloquearía el scroll global.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          activeBusinessCount: overviewAsync.value
              ?.where((b) => b.isActive)
              .length,
          onRefresh: () {
            // Invalidar las FUENTES; los providers filtrados se re-derivan solos.
            ref.invalidate(platformOverviewProvider);
            ref.invalidate(revenueTrend12hProvider);
            ref.invalidate(platformAlertsProvider);
            ref.invalidate(businessWeekTrendProvider);
          },
        ),
        const SizedBox(height: 20),
        // Banner visible solo cuando hay incidentes críticos abiertos.
        const CriticalIncidentsBanner(),
        const SizedBox(height: 16),
        overviewAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
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
              'Error cargando métricas: $e',
              style: const TextStyle(color: AppColors.destructive),
            ),
          ),
          data: (rows) => _MetricsGrid(overview: rows),
        ),
        const SizedBox(height: 24),
        // Chart + AlertsPanel: lado a lado en lg+, apilados en mobile/tablet.
        if (isWide)
          SizedBox(
            height: 360,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(flex: 2, child: RevenueChart()),
                const SizedBox(width: 20),
                const Expanded(flex: 1, child: AlertsPanel()),
              ],
            ),
          )
        else ...[
          const RevenueChart(),
          const SizedBox(height: 20),
          const SizedBox(height: 360, child: AlertsPanel()),
        ],
        const SizedBox(height: 24),
        const BusinessTable(),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.activeBusinessCount, required this.onRefresh});

  final int? activeBusinessCount;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < Breakpoints.tablet;
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'VISTA GLOBAL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Estado de la plataforma',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              activeBusinessCount == null
                  ? 'Resumen ejecutivo de la plataforma MangoPOS.'
                  : 'Resumen ejecutivo de los ${activeBusinessCount!} negocios activos en MangoPOS.',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        );

        final right = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Clock(),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
              label: const Text('Actualizar'),
            ),
          ],
        );

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [left, const SizedBox(height: 12), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: left),
            right,
          ],
        );
      },
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Stream<DateTime> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(
      const Duration(seconds: 1),
      (_) => DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: _ticker,
      initialData: DateTime.now(),
      builder: (context, snap) {
        final now = snap.data ?? DateTime.now();
        // Hora local del dispositivo (la consola se opera desde DR).
        final formatted = DateFormat('HH:mm:ss', 'es_DO').format(now);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.border, width: 0.6),
            borderRadius: BorderRadius.circular(10),
            boxShadow: AppColors.shadowCard,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'HORA LOCAL',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatted,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: AppColors.foreground,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'AST',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.overview});
  final List<BusinessOverview> overview;

  @override
  Widget build(BuildContext context) {
    final m = _aggregate(overview);

    final activeRatio = m.activeBusinesses == 0
        ? 0.0
        : m.businessesOnline / m.activeBusinesses;

    // KPIs primarios — los 4 más importantes, en grilla 2×2 (mobile) o 4×1 (desktop).
    final primaryCards = <Widget>[
      Builder(
        builder: (ctx) => MetricCard(
          label: 'Negocios activos',
          value: '${m.activeBusinesses}',
          sublabel: '${m.businessesOnline} operando ahora',
          icon: HugeIcons.strokeRoundedBuilding03,
          featured: true,
          progress: activeRatio,
          onTap: () => showOperatingNowSheet(ctx, overview),
        ),
      ),
      MetricCard(
        label: 'Ingresos hoy',
        value: formatRd(m.totalRevenueToday),
        sublabel: '${formatInt(m.totalSalesToday)} transacciones',
        icon: HugeIcons.strokeRoundedDollarCircle,
        variant: MetricVariant.accent,
      ),
      MetricCard(
        label: 'NCF emitidos',
        value: formatInt(m.totalNcfToday),
        sublabel: m.ncfCritical + m.ncfWarning > 0
            ? '${m.ncfCritical + m.ncfWarning} con stock bajo'
            : 'Stock saludable',
        icon: HugeIcons.strokeRoundedInvoice03,
        variant: m.ncfCritical > 0
            ? MetricVariant.destructive
            : MetricVariant.success,
      ),
      Builder(
        builder: (ctx) => MetricCard(
          label: 'En operación ahora',
          value: '${m.businessesOnline}/${m.activeBusinesses}',
          sublabel: m.businessesActiveToday > m.businessesOnline
              ? '${m.businessesActiveToday} con uso hoy'
              : 'Última hora',
          icon: HugeIcons.strokeRoundedWifi01,
          variant: m.businessesOnline == 0
              ? MetricVariant.warning
              : MetricVariant.success,
          progress: activeRatio,
          onTap: () => showOperatingNowSheet(ctx, overview),
        ),
      ),
    ];

    // KPIs secundarios — versión compacta.
    final secondaryCards = <Widget>[
      MetricCard(
        compact: true,
        label: 'Fallas impresión 24h',
        value: formatInt(m.printFailures24h),
        sublabel: 'Acumulado',
        icon: HugeIcons.strokeRoundedPrinter,
        variant: m.printFailures24h > 30
            ? MetricVariant.destructive
            : MetricVariant.neutral,
      ),
      MetricCard(
        compact: true,
        label: 'Membresías por vencer',
        value: '${m.expiringSoon}',
        sublabel: 'Próx. 7 días',
        icon: HugeIcons.strokeRoundedAlert02,
        variant: m.expiringSoon > 0
            ? MetricVariant.warning
            : MetricVariant.neutral,
      ),
      MetricCard(
        compact: true,
        label: 'Ticket promedio',
        value: formatRd(
          m.totalSalesToday > 0 ? m.totalRevenueToday / m.totalSalesToday : 0,
        ),
        sublabel: 'Plataforma',
        icon: HugeIcons.strokeRoundedShoppingCart01,
      ),
      MetricCard(
        compact: true,
        label: 'Sesiones abiertas',
        value: formatInt(m.openSessions),
        sublabel: '${formatInt(m.openTables)} mesas',
        icon: HugeIcons.strokeRoundedDashboardCircle,
        variant: MetricVariant.primary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final int cols;
        final double primaryRatio;
        final double secondaryRatio;
        if (w >= 1100) {
          cols = 4;
          primaryRatio = 1.45;
          secondaryRatio = 2.0;
        } else if (w >= 640) {
          cols = 2;
          primaryRatio = 1.25;
          secondaryRatio = 1.85;
        } else {
          cols = 1;
          primaryRatio = 2.6;
          secondaryRatio = 3.6;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: primaryRatio,
              children: primaryCards,
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: secondaryRatio,
              children: secondaryCards,
            ),
          ],
        );
      },
    );
  }

  _AggregatedMetrics _aggregate(List<BusinessOverview> rows) {
    final actives = rows.where((b) => b.isActive).toList();
    return _AggregatedMetrics(
      activeBusinesses: actives.length,
      agentsOnline: actives
          .where((b) => b.agentStatus == AgentStatus.online)
          .length,
      agentsOffline: actives
          .where(
            (b) =>
                b.agentStatus == AgentStatus.offline ||
                b.agentStatus == AgentStatus.none,
          )
          .length,
      totalRevenueToday: actives.fold<double>(0, (s, b) => s + b.revenueToday),
      totalSalesToday: actives.fold<int>(0, (s, b) => s + b.salesToday),
      totalNcfToday: actives.fold<int>(0, (s, b) => s + b.ncfIssuedToday),
      ncfCritical: actives
          .where((b) => b.ncfStatus == NcfStatus.critical)
          .length,
      ncfWarning: actives.where((b) => b.ncfStatus == NcfStatus.warning).length,
      printFailures24h: actives.fold<int>(0, (s, b) => s + b.printFailures24h),
      openSessions: actives.fold<int>(0, (s, b) => s + b.openSessions),
      openTables: actives.fold<int>(0, (s, b) => s + b.openTables),
      expiringSoon: actives.where((b) {
        final d = b.planEndDate;
        if (d == null) return false;
        final days = d.difference(DateTime.now()).inDays;
        return days <= 7;
      }).length,
      businessesOnline: actives
          .where((b) => b.activityStatus == ActivityStatus.online)
          .length,
      businessesActiveToday: actives
          .where((b) =>
              b.activityStatus == ActivityStatus.online ||
              b.activityStatus == ActivityStatus.late ||
              b.activityStatus == ActivityStatus.recent)
          .length,
    );
  }
}

class _AggregatedMetrics {
  const _AggregatedMetrics({
    required this.activeBusinesses,
    required this.agentsOnline,
    required this.agentsOffline,
    required this.totalRevenueToday,
    required this.totalSalesToday,
    required this.totalNcfToday,
    required this.ncfCritical,
    required this.ncfWarning,
    required this.printFailures24h,
    required this.openSessions,
    required this.openTables,
    required this.expiringSoon,
    required this.businessesOnline,
    required this.businessesActiveToday,
  });

  final int activeBusinesses;
  final int agentsOnline;
  final int agentsOffline;
  final double totalRevenueToday;
  final int totalSalesToday;
  final int totalNcfToday;
  final int ncfCritical;
  final int ncfWarning;
  final int printFailures24h;
  final int openSessions;
  final int openTables;
  final int expiringSoon;

  /// Negocios con actividad en los últimos 15 minutos.
  final int businessesOnline;

  /// Negocios con actividad hoy (online + tardío + reciente <24h).
  final int businessesActiveToday;
}

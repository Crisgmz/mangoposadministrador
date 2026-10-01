import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/breakpoints.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/pending_accounts_repository.dart';
import '../../domain/models/business_overview.dart';
import '../incidents/widgets/critical_incidents_banner.dart';
import 'action_queue.dart';
import 'widgets/action_queue_panel.dart';
import 'widgets/business_table.dart';
import 'widgets/kpi_strip.dart';
import 'widgets/operating_now_sheet.dart';
import 'widgets/revenue_chart.dart';
import 'widgets/side_panels.dart';

/// Vista global — pantalla principal de la consola operadora.
///
/// El orden de la página ES la decisión de diseño: qué mira el operador
/// primero. De arriba a abajo:
///
///   1. Cinta de KPIs — el estado en una franja, no en ocho tarjetas.
///   2. Requiere acción — la cola priorizada, con el botón en la fila.
///   3. Ingresos 12 h contra ayer — el pulso del negocio.
///   4. Negocios ordenados por riesgo — el detalle, cuando hace falta.
///
/// En móvil la bandeja sube al primer lugar: quien abre esto desde el
/// teléfono va a apagar un fuego, no a leer métricas.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  /// Cuándo llegaron los datos que se están viendo. Alimenta el "datos hace
  /// Xs" del header: sin eso, una consola en vivo no dice si lo que muestra
  /// es de hace cuatro segundos o de hace cuarenta minutos.
  ///
  /// Es un [ValueNotifier] y no estado del widget a propósito. Con `setState`
  /// —y un timer de un segundo para refrescar la etiqueta— la página ENTERA
  /// se reconstruía cada segundo: gráfico, tabla y bandeja incluidos. Eso se
  /// comía el presupuesto de frame y hacía que todo, incluida la navegación,
  /// se sintiera pesado. Ahora solo se repinta el texto de frescura.
  final ValueNotifier<DateTime> _lastData = ValueNotifier(DateTime.now());

  @override
  void dispose() {
    _lastData.dispose();
    super.dispose();
  }

  void _refresh() {
    // Invalidar las FUENTES; los providers derivados se recalculan solos.
    ref.invalidate(platformOverviewProvider);
    ref.invalidate(revenueTrend12hProvider);
    ref.invalidate(platformAlertsProvider);
    ref.invalidate(businessWeekTrendProvider);
    ref.invalidate(pendingAccountsListProvider);
    ref.invalidate(pendingAccountsCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<BusinessOverview>>>(platformOverviewProvider, (
      _,
      next,
    ) {
      if (next.hasValue && !next.isLoading) {
        _lastData.value = DateTime.now();
      }
    });

    final overviewAsync = ref.watch(filteredOverviewProvider);
    final isWide = Breakpoints.isDesktop(context);
    final rows = overviewAsync.value ?? const <BusinessOverview>[];
    final metrics = _PlatformMetrics.from(rows);
    final queueCount = ref.watch(actionQueueProvider).valueOrNull?.length ?? 0;
    final criticals = ref.watch(criticalActionCountProvider);

    // El scroll vertical lo provee `AppShell.ContentArea`. Aquí solo emitimos
    // la columna de contenido — anidar otro scroll bloquearía el global.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          metrics: metrics,
          criticals: criticals,
          lastData: _lastData,
          onRefresh: _refresh,
        ),
        const SizedBox(height: 20),
        const CriticalIncidentsBanner(),
        const SizedBox(height: 16),

        if (!isWide) ...[
          // Móvil: primero lo que exige acción, recortado a tres filas para
          // que los KPIs y el gráfico sigan alcanzándose con un scroll.
          const ActionQueuePanel(maxRows: 3),
          const SizedBox(height: 16),
        ],

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
          data: (data) => KpiStrip(
            cells: _kpiCells(
              context,
              metrics: metrics,
              rows: data,
              queueCount: queueCount,
              criticals: criticals,
            ),
          ),
        ),
        const SizedBox(height: 20),

        if (isWide) ...[
          // La bandeja lleva alto fijo y las cards laterales el suyo propio:
          // así la columna derecha no se estira con huecos cuando hay pocas
          // cuentas pendientes.
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 19, child: ActionQueuePanel(height: 436)),
              SizedBox(width: 20),
              Expanded(
                flex: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PendingAccountsCard(),
                    SizedBox(height: 16),
                    ExpiringMembershipsCard(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        const RevenueChart(),
        const SizedBox(height: 20),

        if (!isWide) ...[
          const PendingAccountsCard(),
          const SizedBox(height: 16),
          const ExpiringMembershipsCard(),
          const SizedBox(height: 20),
        ],

        // En Vista Global la tabla es un resumen: las primeras filas por
        // riesgo y un enlace al listado completo.
        BusinessTable(
          maxRows: isWide ? 6 : 3,
          title: isWide ? 'Negocios' : 'Negocios en riesgo',
          showToolbar: isWide,
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  List<KpiCell> _kpiCells(
    BuildContext context, {
    required _PlatformMetrics metrics,
    required List<BusinessOverview> rows,
    required int queueCount,
    required int criticals,
  }) {
    final ratio = metrics.activeBusinesses == 0
        ? 0.0
        : metrics.businessesOnline / metrics.activeBusinesses;
    final ticket = metrics.totalSalesToday > 0
        ? metrics.totalRevenueToday / metrics.totalSalesToday
        : 0.0;

    return [
      KpiCell(
        label: 'OPERANDO AHORA',
        value: '${metrics.businessesOnline}/${metrics.activeBusinesses}',
        sublabel: metrics.agentsDown > 0
            ? '${metrics.agentsDown} sin latido'
            : 'todos con latido',
        icon: KpiIcons.operating,
        color: AppColors.primary,
        progress: ratio,
        onTap: () => showOperatingNowSheet(context, rows),
      ),
      KpiCell(
        label: 'REQUIERE ACCIÓN',
        value: '$queueCount',
        sublabel: criticals > 0
            ? '$criticals ${criticals == 1 ? "crítica" : "críticas"}'
            : 'nada crítico',
        icon: KpiIcons.inbox,
        color: criticals > 0
            ? AppColors.destructive
            : AppColors.mutedForeground,
      ),
      KpiCell(
        label: 'INGRESOS HOY',
        value: formatRdShort(metrics.totalRevenueToday),
        sublabel:
            '${formatInt(metrics.totalSalesToday)} tx · ticket '
            '${formatRdCompact(ticket)}',
        icon: KpiIcons.revenue,
        color: AppColors.accent,
      ),
      KpiCell(
        label: 'NCF EMITIDOS',
        value: formatInt(metrics.totalNcfToday),
        sublabel: metrics.ncfLow > 0
            ? '${metrics.ncfLow} ${metrics.ncfLow == 1 ? "secuencia baja" : "secuencias bajas"}'
            : 'stock saludable',
        icon: KpiIcons.ncf,
        color: metrics.ncfCritical > 0
            ? AppColors.destructive
            : AppColors.primary,
      ),
      KpiCell(
        label: 'FALLAS IMPR. 24H',
        value: formatInt(metrics.printFailures24h),
        sublabel: metrics.businessesWithFailures > 0
            ? 'en ${metrics.businessesWithFailures} '
                  '${metrics.businessesWithFailures == 1 ? "negocio" : "negocios"}'
            : 'sin fallas',
        icon: KpiIcons.printing,
        color: metrics.printFailures24h > 30
            ? AppColors.destructive
            : AppColors.warning,
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.metrics,
    required this.criticals,
    required this.lastData,
    required this.onRefresh,
  });

  final _PlatformMetrics metrics;
  final int criticals;
  final ValueListenable<DateTime> lastData;
  final VoidCallback onRefresh;

  String get _subtitle {
    final parts = <String>[
      '${metrics.activeBusinesses} '
          '${metrics.activeBusinesses == 1 ? "negocio activo" : "negocios activos"}',
      '${metrics.businessesOnline} operando ahora',
      if (criticals > 0)
        '$criticals ${criticals == 1 ? "requiere" : "requieren"} atención '
            'inmediata',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < Breakpoints.tablet;
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
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
              _subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        );

        final right = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reloj y "hace Xs" repintan cada segundo: en su propia capa, así
            // no arrastran al encabezado ni a la página.
            const RepaintBoundary(child: _Clock()),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(HugeIcons.strokeRoundedRefresh, size: 16),
                  label: const Text('Actualizar'),
                ),
                const SizedBox(height: 3),
                RepaintBoundary(child: _DataFreshness(lastData: lastData)),
              ],
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

/// "datos hace 4s". Tiene su propio timer y se repinta solo él: es la única
/// parte del header que necesita cambiar cada segundo.
class _DataFreshness extends StatefulWidget {
  const _DataFreshness({required this.lastData});

  final ValueListenable<DateTime> lastData;

  @override
  State<_DataFreshness> createState() => _DataFreshnessState();
}

class _DataFreshnessState extends State<_DataFreshness> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: widget.lastData,
      builder: (context, value, _) => Text(
        'datos ${formatRelative(value)}',
        style: const TextStyle(
          fontSize: 10.5,
          fontFamily: 'monospace',
          color: AppColors.mutedForeground,
        ),
      ),
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
                crossAxisAlignment: CrossAxisAlignment.end,
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

/// Agregados de plataforma que alimentan header y cinta de KPIs.
class _PlatformMetrics {
  const _PlatformMetrics({
    required this.activeBusinesses,
    required this.businessesOnline,
    required this.agentsDown,
    required this.totalRevenueToday,
    required this.totalSalesToday,
    required this.totalNcfToday,
    required this.ncfCritical,
    required this.ncfLow,
    required this.printFailures24h,
    required this.businessesWithFailures,
  });

  final int activeBusinesses;

  /// Con señal de uso en los últimos 15 minutos.
  final int businessesOnline;

  /// Con el agente sin reportar (caído o nunca instalado).
  final int agentsDown;

  final double totalRevenueToday;
  final int totalSalesToday;
  final int totalNcfToday;
  final int ncfCritical;

  /// Secuencias en advertencia o crítica — las dos frenan la facturación.
  final int ncfLow;

  final int printFailures24h;
  final int businessesWithFailures;

  factory _PlatformMetrics.from(List<BusinessOverview> rows) {
    final actives = rows.where((b) => b.isActive).toList(growable: false);
    return _PlatformMetrics(
      activeBusinesses: actives.length,
      businessesOnline: actives
          .where((b) => b.activityStatus == ActivityStatus.online)
          .length,
      agentsDown: actives
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
      ncfLow: actives.where((b) => b.ncfStatus != NcfStatus.ok).length,
      printFailures24h: actives.fold<int>(0, (s, b) => s + b.printFailures24h),
      businessesWithFailures: actives
          .where((b) => b.printFailures24h > 0)
          .length,
    );
  }
}

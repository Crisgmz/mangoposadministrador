// Render de Vista Global v2 con datos falsos, en escritorio y en móvil.
//
// Lo que protege: que la página se arme sin overflows ni excepciones en los
// dos breakpoints, y que la bandeja "Requiere acción" ordene por severidad.
// Es el tipo de rotura que sólo aparece al abrir la app.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mangopos_administrador/data/repositories/dashboard_repository.dart';
import 'package:mangopos_administrador/data/repositories/incidents_repository.dart';
import 'package:mangopos_administrador/data/repositories/pending_accounts_repository.dart';
import 'package:mangopos_administrador/data/repositories/plans_repository.dart';
import 'package:mangopos_administrador/domain/models/business_environment.dart';
import 'package:mangopos_administrador/domain/models/business_overview.dart';
import 'package:mangopos_administrador/domain/models/noc_incident.dart';
import 'package:mangopos_administrador/domain/models/pending_business.dart';
import 'package:mangopos_administrador/domain/models/plan.dart';
import 'package:mangopos_administrador/domain/models/platform_alert.dart';
import 'package:mangopos_administrador/domain/models/revenue_hour.dart';
import 'package:mangopos_administrador/presentation/dashboard/action_queue.dart';
import 'package:mangopos_administrador/presentation/dashboard/dashboard_page.dart';

BusinessOverview _business({
  required String id,
  required String name,
  AgentStatus agent = AgentStatus.online,
  ActivityStatus activity = ActivityStatus.online,
  NcfStatus ncf = NcfStatus.ok,
  int printFailures = 0,
  int openSessions = 1,
  double revenue = 10000,
  String status = 'active',
}) {
  return BusinessOverview(
    id: id,
    name: name,
    businessType: 'restaurante',
    status: status,
    domain: '$id.mangopos.do',
    plan: PlanType.pro,
    planEndDate: DateTime.now().add(const Duration(days: 4)),
    agentStatus: agent,
    agentLastSeen: DateTime.now().subtract(const Duration(minutes: 1)),
    agentName: 'agente-01',
    salesToday: 100,
    revenueToday: revenue,
    ncfAvailable: 500,
    ncfStatus: ncf,
    ncfIssuedToday: 80,
    printJobsToday: 200,
    printFailures24h: printFailures,
    openSessions: openSessions,
    openTables: 2,
    environment: BusinessEnvironment.production,
    activityStatus: activity,
    lastActivityAt: DateTime.now().subtract(const Duration(days: 2)),
  );
}

PlatformAlert _alert({
  required AlertType type,
  required AlertSeverity severity,
  required String businessName,
  DateTime? at,
}) {
  return PlatformAlert(
    type: type,
    severity: severity,
    businessId: 'b-alert',
    businessName: businessName,
    label: 'Alerta de $businessName',
    detail: 'detalle',
    referenceAt: at ?? DateTime.now().subtract(const Duration(hours: 1)),
    environment: BusinessEnvironment.production,
  );
}

final _rows = <BusinessOverview>[
  _business(id: 'b1', name: 'Pollos El Sabor'),
  _business(
    id: 'b2',
    name: 'Barbería Style',
    agent: AgentStatus.offline,
    activity: ActivityStatus.inactive,
    ncf: NcfStatus.critical,
    printFailures: 24,
  ),
  _business(id: 'b3', name: 'Cafetería Doña Rosa', agent: AgentStatus.late),
  _business(
    id: 'b4',
    name: 'Farmacia Vida',
    agent: AgentStatus.none,
    activity: ActivityStatus.inactive,
    openSessions: 0,
    revenue: 0,
  ),
];

final _alerts = <PlatformAlert>[
  _alert(
    type: AlertType.planExpiring,
    severity: AlertSeverity.warning,
    businessName: 'Farmacia Vida',
  ),
  _alert(
    type: AlertType.agentOffline,
    severity: AlertSeverity.critical,
    businessName: 'Barbería Style',
  ),
];

final _pending = <PendingBusiness>[
  PendingBusiness(
    businessId: 'p1',
    businessName: 'Repuestos JM',
    status: 'pending',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
    hasVerifiedCard: true,
  ),
];

List<Override> _overrides() => [
  platformOverviewProvider.overrideWith((_) async => _rows),
  platformAlertsProvider.overrideWith((_) async => _alerts),
  revenueTrend12hProvider.overrideWith(
    (_) async => [
      for (var i = 0; i < 12; i++)
        RevenueHour(
          hour: DateTime.now().subtract(Duration(hours: 11 - i)),
          label: '${(9 + i) % 24}:00',
          revenue: 1000.0 * (i + 1),
          transactions: 10 * (i + 1),
          revenuePrev: 900.0 * (i + 1),
          transactionsPrev: 9 * (i + 1),
        ),
    ],
  ),
  pendingAccountsListProvider.overrideWith((_) async => _pending),
  pendingAccountsCountProvider.overrideWith((_) async => _pending.length),
  plansListProvider.overrideWith(
    (_) async => <Plan>[
      Plan(
        code: 'pro',
        name: 'Pro',
        priceMonthly: 4500,
        currencyCode: 'DOP',
        features: const [],
        displayOrder: 1,
        isActive: true,
        taxIncluded: true,
        activeSubscribers: 3,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ],
  ),
  criticalOpenIncidentsProvider.overrideWith((_) async => <NocIncident>[]),
  activeIncidentsCountProvider.overrideWith((_) async => 0),
  businessWeekTrendProvider.overrideWith((_) async => []),
];

Future<void> _pumpDashboard(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(),
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: DashboardPage())),
      ),
    ),
  );
  await tester.pump(); // resuelve los FutureProviders
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_DO', null);
    await initializeDateFormatting('es', null);
  });

  testWidgets('escritorio 1440 renderiza cinta, bandeja y tabla', (
    tester,
  ) async {
    await _pumpDashboard(tester, const Size(1440, 1400));

    expect(find.text('Estado de la plataforma'), findsOneWidget);
    expect(find.text('OPERANDO AHORA'), findsOneWidget);
    expect(find.text('REQUIERE ACCIÓN'), findsOneWidget);
    expect(find.text('Requiere acción'), findsOneWidget);
    expect(find.text('Ingresos últimas 12 horas'), findsOneWidget);
    expect(find.text('Cuentas pendientes'), findsOneWidget);
    expect(find.text('Membresías por vencer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('móvil 390 renderiza sin excepciones', (tester) async {
    await _pumpDashboard(tester, const Size(390, 2200));

    expect(find.text('Estado de la plataforma'), findsOneWidget);
    expect(find.text('Requiere acción'), findsOneWidget);
    expect(find.text('Negocios en riesgo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la bandeja ordena crítico antes que alto y medio', (
    tester,
  ) async {
    late List<ActionItem> queue;
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(),
        child: Consumer(
          builder: (context, ref, _) {
            queue = ref.watch(actionQueueProvider).valueOrNull ?? const [];
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    expect(queue, isNotEmpty);
    final severities = queue.map((i) => i.severity.index).toList();
    final sorted = [...severities]..sort();
    expect(severities, sorted, reason: 'la cola debe venir ordenada');

    // El agente caído y la caja abierta sin latido son críticos.
    expect(
      queue.where((i) => i.severity == ActionSeverity.critical),
      isNotEmpty,
    );
    // La cuenta pendiente va al fondo.
    expect(queue.last.kind, ActionKind.pending);
  });
}

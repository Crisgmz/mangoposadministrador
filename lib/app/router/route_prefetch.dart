import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/cash_health_repository.dart';
import '../../data/repositories/company_settings_repository.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/fiscal_health_repository.dart';
import '../../data/repositories/incidents_repository.dart';
import '../../data/repositories/infrastructure_repository.dart';
import '../../data/repositories/pending_accounts_repository.dart';
import '../../data/repositories/plans_repository.dart';
import '../../data/repositories/print_health_repository.dart';
import '../../data/repositories/table_health_repository.dart';

/// Arranca la carga de los datos de una sección ANTES de entrar.
///
/// Cada sección pide 1–4 RPCs la primera vez que se abre, a ~150 ms o más cada
/// una contra el servidor. Sin esto, la transición terminaba en un spinner y
/// la navegación se sentía lenta aunque la animación fuera rápida. Con esto,
/// lo que tarda el operador entre apoyar el mouse y hacer click ya va
/// adelantando esas llamadas.
///
/// Son los mismos providers que la página observa (no autoDispose), así que
/// la página los encuentra cargando o ya resueltos y no vuelve a pedir nada. Si
/// la sección ya se visitó, no hace ninguna llamada.
void prefetchRoute(WidgetRef ref, String path) {
  final List<FutureProvider<Object?>> providers = switch (path) {
    '/' => [
      platformOverviewProvider,
      platformAlertsProvider,
      revenueTrend12hProvider,
      pendingAccountsListProvider,
    ],
    '/negocios' => [platformOverviewProvider],
    '/incidentes' => [
      incidentSummaryProvider,
      incidentsListProvider,
      criticalOpenIncidentsProvider,
    ],
    '/alertas' => [platformAlertsProvider],
    '/infraestructura' => [vpsStatusProvider],
    '/cajas' => [cashHealthOverviewProvider],
    '/mesas' => [
      tableHealthSummaryProvider,
      zombieSessionsProvider,
      stuckPaymentsProvider,
      orphanItemsProvider,
    ],
    '/fiscal' => [
      fiscalHealthSummaryProvider,
      fiscalProblemsProvider,
      ncfSequencesProvider,
    ],
    '/impresion' => [
      printHealthSummaryProvider,
      printAgentsProvider,
      printJobsProvider,
      printTopFailuresProvider,
    ],
    '/pendientes' => [pendingAccountsListProvider],
    '/facturacion' => [billingOverviewProvider, billingMetricsProvider],
    '/planes' => [plansListProvider],
    '/auditoria' => [criticalAuditLogsProvider(null)],
    '/configuracion' => [companySettingsProvider],
    _ => const [],
  };

  for (final provider in providers) {
    // Un error acá no se muestra: queda guardado en el provider y la página
    // lo presenta con su estado de error normal al entrar.
    ref.read(provider.future).ignore();
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/formatters.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/pending_accounts_repository.dart';
import '../../domain/models/business_overview.dart';
import '../../domain/models/pending_business.dart';
import '../../domain/models/platform_alert.dart';

/// Qué clase de problema es. Determina el botón inline y a dónde lleva.
enum ActionKind {
  /// Agente de impresión sin heartbeat.
  agentDown,

  /// El POS dejó de reportar con caja abierta.
  noHeartbeat,

  /// Secuencia de comprobantes fiscales por agotarse.
  ncf,

  /// Membresía por vencer o vencida.
  dues,

  /// Trabajos de impresión fallando en volumen.
  printing,

  /// Cuenta nueva esperando aprobación.
  pending,
}

/// Severidad operativa. Ordena la bandeja: lo crítico primero.
enum ActionSeverity { critical, high, medium }

/// Filtro de la bandeja. `null` = todo.
enum ActionFilter { down, ncf, pending, dues }

/// Una entrada de la bandeja "Requiere acción".
///
/// Unifica en una sola lista lo que antes vivía en tres paneles distintos
/// (alertas, cuentas pendientes, cobros). El operador no tiene que decidir
/// dónde mirar: lo urgente sube solo.
class ActionItem {
  const ActionItem({
    required this.kind,
    required this.severity,
    required this.businessId,
    required this.businessName,
    required this.title,
    required this.meta,
    required this.actionLabel,
    this.since,
    this.pendingBusiness,
  });

  final ActionKind kind;
  final ActionSeverity severity;
  final String businessId;
  final String businessName;

  /// Qué pasó, en una línea.
  final String title;

  /// Detalle corto en monoespaciada: tiempos, conteos, secuencias.
  final String meta;

  /// Texto del botón inline.
  final String actionLabel;

  /// Desde cuándo. Desempata dentro de la misma severidad: entre dos
  /// críticas, primero la que lleva más tiempo sin resolverse.
  final DateTime? since;

  /// Solo para [ActionKind.pending] — el detalle completo de la cuenta, que
  /// es lo que necesita el diálogo de aprobación.
  final PendingBusiness? pendingBusiness;

  ActionFilter get filter => switch (kind) {
    ActionKind.agentDown ||
    ActionKind.noHeartbeat ||
    ActionKind.printing => ActionFilter.down,
    ActionKind.ncf => ActionFilter.ncf,
    ActionKind.dues => ActionFilter.dues,
    ActionKind.pending => ActionFilter.pending,
  };
}

/// Filtro activo de la bandeja.
final actionQueueFilterProvider = StateProvider<ActionFilter?>((_) => null);

/// La bandeja completa, ya ordenada por severidad y antigüedad.
///
/// El estado (cargando / error) lo marca la fuente principal —las alertas de
/// plataforma—; el resto de fuentes se suman a medida que llegan en vez de
/// bloquear la lista entera.
final actionQueueProvider = Provider<AsyncValue<List<ActionItem>>>((ref) {
  final alertsAsync = ref.watch(filteredAlertsProvider);
  final overview = ref.watch(filteredOverviewProvider).valueOrNull ?? const [];
  final pending =
      ref.watch(pendingAccountsListProvider).valueOrNull ?? const [];

  return alertsAsync.whenData((alerts) {
    final items = <ActionItem>[
      ...alerts.map(_fromAlert),
      ..._fromOverview(overview),
      ...pending.map(_fromPending),
    ];

    items.sort((a, b) {
      final bySeverity = a.severity.index.compareTo(b.severity.index);
      if (bySeverity != 0) return bySeverity;
      final sa = a.since;
      final sb = b.since;
      if (sa == null && sb == null) {
        return a.businessName.compareTo(b.businessName);
      }
      if (sa == null) return 1;
      if (sb == null) return -1;
      return sa.compareTo(sb); // más viejo primero
    });
    return List<ActionItem>.unmodifiable(items);
  });
});

/// Conteo por filtro, para los chips. Incluye el total bajo `null`.
final actionQueueCountsProvider = Provider<Map<ActionFilter?, int>>((ref) {
  final items = ref.watch(actionQueueProvider).valueOrNull ?? const [];
  final counts = <ActionFilter?, int>{null: items.length};
  for (final f in ActionFilter.values) {
    counts[f] = items.where((i) => i.filter == f).length;
  }
  return counts;
});

/// La bandeja con el filtro de chips ya aplicado.
final filteredActionQueueProvider = Provider<AsyncValue<List<ActionItem>>>((
  ref,
) {
  final filter = ref.watch(actionQueueFilterProvider);
  return ref.watch(actionQueueProvider).whenData((items) {
    if (filter == null) return items;
    return items.where((i) => i.filter == filter).toList(growable: false);
  });
});

/// Cuántas de las entradas son críticas — el número que va en rojo.
final criticalActionCountProvider = Provider<int>((ref) {
  final items = ref.watch(actionQueueProvider).valueOrNull ?? const [];
  return items.where((i) => i.severity == ActionSeverity.critical).length;
});

// ── Constructores por fuente ───────────────────────────────────────────────

ActionItem _fromAlert(PlatformAlert alert) {
  final critical = alert.severity == AlertSeverity.critical;
  final severity = critical ? ActionSeverity.critical : ActionSeverity.high;

  switch (alert.type) {
    case AlertType.agentOffline:
      return ActionItem(
        kind: ActionKind.agentDown,
        severity: severity,
        businessId: alert.businessId,
        businessName: alert.businessName,
        title: alert.label.isEmpty ? 'Agente de impresión caído' : alert.label,
        meta: _join([alert.detail, formatRelative(alert.referenceAt)]),
        actionLabel: 'Ver agente',
        since: alert.referenceAt,
      );
    case AlertType.ncfCritical:
      return ActionItem(
        kind: ActionKind.ncf,
        severity: severity,
        businessId: alert.businessId,
        businessName: alert.businessName,
        title: alert.label.isEmpty ? 'NCF por agotarse' : alert.label,
        meta: alert.detail,
        actionLabel: 'Asignar',
        since: alert.referenceAt,
      );
    case AlertType.planExpiring:
      return ActionItem(
        kind: ActionKind.dues,
        severity: severity,
        businessId: alert.businessId,
        businessName: alert.businessName,
        title: alert.label.isEmpty ? 'Membresía por vencer' : alert.label,
        meta: alert.detail,
        actionLabel: 'Cobrar',
        since: alert.referenceAt,
      );
    case AlertType.unknown:
      return ActionItem(
        kind: ActionKind.agentDown,
        severity: severity,
        businessId: alert.businessId,
        businessName: alert.businessName,
        title: alert.label.isEmpty ? 'Requiere revisión' : alert.label,
        meta: alert.detail,
        actionLabel: 'Ver',
        since: alert.referenceAt,
      );
  }
}

/// Señales que salen de la tabla de negocios y que ninguna alerta cubre.
///
/// El umbral es deliberadamente alto en los dos casos: un negocio cerrado no
/// es una emergencia y una impresora con dos fallos tampoco. Se avisa cuando
/// hay dinero expuesto (caja abierta sin latido) o cuando el volumen de
/// fallos ya no puede ser un incidente aislado.
Iterable<ActionItem> _fromOverview(List<BusinessOverview> rows) sync* {
  for (final b in rows) {
    if (!b.isActive) continue;

    if (b.activityStatus == ActivityStatus.inactive && b.openSessions > 0) {
      yield ActionItem(
        kind: ActionKind.noHeartbeat,
        severity: ActionSeverity.critical,
        businessId: b.id,
        businessName: b.name,
        title: 'Sin latido con caja abierta',
        meta: _join([
          'últ. señal ${formatRelative(b.lastActivityAt)}',
          '${b.openSessions} ${b.openSessions == 1 ? "caja" : "cajas"}',
        ]),
        actionLabel: 'Ver caja',
        since: b.lastActivityAt,
      );
    }

    if (b.printFailures24h >= 10) {
      yield ActionItem(
        kind: ActionKind.printing,
        severity: b.printFailures24h >= 20
            ? ActionSeverity.critical
            : ActionSeverity.high,
        businessId: b.id,
        businessName: b.name,
        title: '${b.printFailures24h} fallas de impresión en 24 h',
        meta: '${b.printJobsToday} envíos hoy',
        actionLabel: 'Ver',
        since: null,
      );
    }
  }
}

ActionItem _fromPending(PendingBusiness p) {
  return ActionItem(
    kind: ActionKind.pending,
    severity: ActionSeverity.medium,
    businessId: p.businessId,
    businessName: p.businessName,
    title: 'Cuenta pendiente de aprobación',
    meta: _join([
      formatRelative(p.createdAt),
      p.hasVerifiedCard ? 'tarjeta verificada' : 'sin tarjeta',
    ]),
    actionLabel: 'Aprobar',
    since: p.createdAt,
    pendingBusiness: p,
  );
}

String _join(List<String> parts) =>
    parts.where((p) => p.trim().isNotEmpty).join(' · ');

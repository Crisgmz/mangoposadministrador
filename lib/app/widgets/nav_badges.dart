import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/incidents_repository.dart';
import '../../data/repositories/pending_accounts_repository.dart';
import '../../domain/models/business_overview.dart';
import '../theme/app_colors.dart';
import 'nav_items.dart';

/// Resuelve el contador de un item de navegación.
///
/// Un solo punto para los cuatro badges: sidebar y bottom nav leen de acá, así
/// que no puede pasar que el móvil diga 3 incidentes y el escritorio 2.
///
/// Devuelve `null` mientras el provider de origen carga o falla — el badge
/// simplemente no se pinta en vez de mostrar un cero que se leería como
/// "todo tranquilo".
final navBadgeCountProvider = Provider.family<int?, NavBadge>((ref, badge) {
  switch (badge) {
    case NavBadge.none:
      return null;
    case NavBadge.incidents:
      return ref.watch(activeIncidentsCountProvider).valueOrNull;
    case NavBadge.alerts:
      return ref.watch(filteredAlertsProvider).valueOrNull?.length;
    case NavBadge.ncf:
      // Secuencias en advertencia o críticas: las dos frenan la facturación
      // si nadie asigna comprobantes, así que cuentan igual.
      return ref
          .watch(filteredOverviewProvider)
          .valueOrNull
          ?.where((b) => b.isActive && b.ncfStatus != NcfStatus.ok)
          .length;
    case NavBadge.pending:
      return ref.watch(pendingAccountsCountProvider).valueOrNull;
  }
});

/// Color del badge según lo que representa. Rojo = algo está caído ahora;
/// ámbar = se va a romper pronto; naranja de marca = hay trabajo esperando.
Color navBadgeColor(NavBadge badge) => switch (badge) {
  NavBadge.incidents => AppColors.destructive,
  NavBadge.ncf => AppColors.warning,
  _ => AppColors.accent,
};

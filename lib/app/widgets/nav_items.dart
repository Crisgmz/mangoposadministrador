import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Bloque temático de la navegación.
///
/// Catorce destinos planos obligaban a leer la lista entera para encontrar
/// uno. Agrupados por el tipo de trabajo que resuelven —apagar fuegos, vigilar
/// salud, cobrar, administrar— el operador salta directo al bloque que le
/// toca.
enum NavSection {
  /// Lo que se mira primero y lo que se rompe.
  operacion('OPERACIÓN'),

  /// Vigilancia continua de los subsistemas del POS.
  salud('SALUD'),

  /// Dinero: cuentas nuevas, cobros y planes.
  comercial('COMERCIAL'),

  /// Rastro y configuración de la consola.
  sistema('SISTEMA');

  const NavSection(this.label);
  final String label;
}

/// Contador que se muestra pegado al item. El origen del número vive en el
/// widget que pinta la navegación (ahí están los providers); acá solo se
/// declara CUÁL contador corresponde a cada destino, para que sidebar y
/// bottom nav no se desincronicen.
enum NavBadge {
  none,

  /// Incidentes abiertos — rojo: hay algo caído ahora.
  incidents,

  /// Alertas activas de plataforma.
  alerts,

  /// Secuencias NCF en advertencia o críticas — ámbar: se agota el papel
  /// fiscal y eso frena la facturación.
  ncf,

  /// Cuentas por aprobar.
  pending,
}

/// Definición de un item de navegación de la consola.
///
/// El mismo set se usa en `Sidebar` (desktop) y `BottomNav` (móvil),
/// aunque BottomNav muestra un subconjunto.
class NavItem {
  const NavItem({
    required this.path,
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.section,
    this.badge = NavBadge.none,
    this.showInBottomNav = true,
  });

  final String path;
  final String label;
  final String shortLabel;
  final IconData icon;
  final NavSection section;
  final NavBadge badge;
  final bool showInBottomNav;
}

const List<NavItem> kNavItems = [
  // ── Operación ───────────────────────────────────────────────────────────
  NavItem(
    path: '/',
    label: 'Vista global',
    shortLabel: 'Inicio',
    icon: HugeIcons.strokeRoundedDashboardSquare02,
    section: NavSection.operacion,
  ),
  NavItem(
    path: '/negocios',
    label: 'Negocios',
    shortLabel: 'Negocios',
    icon: HugeIcons.strokeRoundedBuilding03,
    section: NavSection.operacion,
  ),
  NavItem(
    path: '/incidentes',
    label: 'Incidentes',
    shortLabel: 'Incidentes',
    icon: HugeIcons.strokeRoundedAlertCircle,
    section: NavSection.operacion,
    badge: NavBadge.incidents,
    showInBottomNav: false,
  ),
  NavItem(
    path: '/alertas',
    label: 'Alertas',
    shortLabel: 'Alertas',
    icon: HugeIcons.strokeRoundedNotification03,
    section: NavSection.operacion,
    badge: NavBadge.alerts,
  ),
  NavItem(
    path: '/infraestructura',
    label: 'Infraestructura',
    shortLabel: 'Infra',
    icon: HugeIcons.strokeRoundedCpu,
    section: NavSection.operacion,
    showInBottomNav: false,
  ),

  // ── Salud ───────────────────────────────────────────────────────────────
  NavItem(
    path: '/cajas',
    label: 'Salud de cajas',
    shortLabel: 'Cajas',
    icon: HugeIcons.strokeRoundedDashboardCircle,
    section: NavSection.salud,
  ),
  NavItem(
    path: '/mesas',
    label: 'Salud de mesas',
    shortLabel: 'Mesas',
    icon: HugeIcons.strokeRoundedTable02,
    section: NavSection.salud,
    showInBottomNav: false,
  ),
  NavItem(
    path: '/fiscal',
    label: 'Fiscal / NCF',
    shortLabel: 'Fiscal',
    icon: HugeIcons.strokeRoundedReceiptDollar,
    section: NavSection.salud,
    badge: NavBadge.ncf,
  ),
  NavItem(
    path: '/impresion',
    label: 'Impresión',
    shortLabel: 'Impresión',
    icon: HugeIcons.strokeRoundedPrinter,
    section: NavSection.salud,
    showInBottomNav: false,
  ),

  // ── Comercial ───────────────────────────────────────────────────────────
  NavItem(
    path: '/pendientes',
    label: 'Cuentas pendientes',
    shortLabel: 'Pendientes',
    icon: HugeIcons.strokeRoundedClock04,
    section: NavSection.comercial,
    badge: NavBadge.pending,
    showInBottomNav: false,
  ),
  NavItem(
    path: '/facturacion',
    label: 'Facturación',
    shortLabel: 'Cobros',
    icon: HugeIcons.strokeRoundedInvoice03,
    section: NavSection.comercial,
    showInBottomNav: false,
  ),
  NavItem(
    path: '/planes',
    label: 'Planes y precios',
    shortLabel: 'Planes',
    icon: HugeIcons.strokeRoundedTag01,
    section: NavSection.comercial,
    showInBottomNav: false,
  ),

  // ── Sistema ─────────────────────────────────────────────────────────────
  NavItem(
    path: '/auditoria',
    label: 'Auditoría',
    shortLabel: 'Auditoría',
    icon: HugeIcons.strokeRoundedNote04,
    section: NavSection.sistema,
    showInBottomNav: false,
  ),
  NavItem(
    path: '/configuracion',
    label: 'Configuración',
    shortLabel: 'Config',
    icon: HugeIcons.strokeRoundedSettings02,
    section: NavSection.sistema,
    showInBottomNav: false,
  ),
];

/// Items de una sección, en el orden declarado arriba.
List<NavItem> navItemsOf(NavSection section) =>
    kNavItems.where((i) => i.section == section).toList(growable: false);

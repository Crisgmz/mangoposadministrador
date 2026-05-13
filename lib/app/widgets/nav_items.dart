import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

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
    this.showInBottomNav = true,
  });

  final String path;
  final String label;
  final String shortLabel;
  final IconData icon;
  final bool showInBottomNav;
}

const List<NavItem> kNavItems = [
  NavItem(
    path: '/',
    label: 'Vista global',
    shortLabel: 'Inicio',
    icon: HugeIcons.strokeRoundedDashboardSquare02,
  ),
  NavItem(
    path: '/negocios',
    label: 'Negocios',
    shortLabel: 'Negocios',
    icon: HugeIcons.strokeRoundedBuilding03,
  ),
  NavItem(
    path: '/cajas',
    label: 'Salud de cajas',
    shortLabel: 'Cajas',
    icon: HugeIcons.strokeRoundedDashboardCircle,
  ),
  NavItem(
    path: '/mesas',
    label: 'Salud de mesas',
    shortLabel: 'Mesas',
    icon: HugeIcons.strokeRoundedTable02,
    showInBottomNav: false,
  ),
  NavItem(
    path: '/facturacion',
    label: 'Facturación',
    shortLabel: 'Cobros',
    icon: HugeIcons.strokeRoundedInvoice03,
    showInBottomNav: false,
  ),
  NavItem(
    path: '/fiscal',
    label: 'Fiscal / NCF',
    shortLabel: 'Fiscal',
    icon: HugeIcons.strokeRoundedReceiptDollar,
  ),
  NavItem(
    path: '/impresion',
    label: 'Impresión',
    shortLabel: 'Impresión',
    icon: HugeIcons.strokeRoundedPrinter,
    showInBottomNav: false,
  ),
  NavItem(
    path: '/auditoria',
    label: 'Auditoría',
    shortLabel: 'Auditoría',
    icon: HugeIcons.strokeRoundedNote04,
    showInBottomNav: false,
  ),
  NavItem(
    path: '/alertas',
    label: 'Alertas',
    shortLabel: 'Alertas',
    icon: HugeIcons.strokeRoundedNotification03,
  ),
  NavItem(
    path: '/incidentes',
    label: 'Incidentes',
    shortLabel: 'Incidentes',
    icon: HugeIcons.strokeRoundedAlertCircle,
    showInBottomNav: false,
  ),
];

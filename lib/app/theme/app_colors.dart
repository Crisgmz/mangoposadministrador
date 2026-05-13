import 'package:flutter/material.dart';

/// Tokens de color del prototipo `mango-overview-desk` portados desde HSL.
///
/// Verde institucional + naranja de acento. Mantener nombres lo más cerca
/// posible de los CSS variables del prototipo (`--primary`, `--accent`, ...).
class AppColors {
  AppColors._();

  // Base — fondo blanco (cards y página comparten color, separación por borde + sombra)
  static const background = Color(0xFFFFFFFF);
  static const foreground = Color(0xFF0F1F17); // 145 35% 9%  — deep forest
  static const card = Color(0xFFFFFFFF);
  static const cardForeground = foreground;
  static const popover = card;
  static const popoverForeground = foreground;

  // Verde MangoPOS — color de marca oficial
  static const primary = Color(0xFF32AE40); // 127 55% 44%
  static const primaryGlow = Color(0xFF56C863); // 127 51% 56% — variante clara
  static const primaryForeground = background;

  // Naranja acento — color de marca oficial
  static const accent = Color(0xFFF7951A); // 33 93% 54%
  static const accentForeground = Color(0xFFFFFFFF);
  static const accentSoft = Color(0xFFFEF3E7); // 33 90% 95%

  // Secondary / muted — neutrales gris claro (mejor contraste sobre fondo blanco)
  static const secondary = Color(0xFFF1F5F2); // verde-gris muy pálido
  static const secondaryForeground = foreground;
  static const muted = Color(0xFFF4F4F5); // 240 5% 96% — gris neutro para inputs/chips
  static const mutedForeground = Color(0xFF566159); // 145 10% 38%

  // Status
  static const destructive = Color(0xFFDC2626); // 0 75% 50%
  static const destructiveForeground = Color(0xFFFFFFFF);
  static const warning = Color(0xFFF59E0B); // 38 92% 50%
  static const warningForeground = foreground;
  static const success = primary;
  static const successForeground = Color(0xFFFFFFFF);

  // Border / input / ring — más visibles sobre fondo blanco
  static const border = Color(0xFFE5E7EB); // 220 13% 91% — gris neutro
  static const input = border;
  static const ring = primary;

  // Sidebar (verde oscuro)
  static const sidebarBackground = Color(0xFF0F1F17); // 145 35% 9%
  static const sidebarForeground = Color(0xFFE6E0D2); // 40 25% 88%
  static const sidebarPrimary = accent;
  static const sidebarPrimaryForeground = Color(0xFFFFFFFF);
  static const sidebarAccent = Color(0xFF18301F); // 145 30% 14%
  static const sidebarAccentForeground = background;
  static const sidebarBorder = Color(0xFF233A2C); // 145 25% 18%
  static const sidebarRing = primaryGlow;

  // Gradients (helpers)
  static const gradientPrimary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryGlow],
  );
  static const gradientAccent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, Color(0xFFF8AC4E)], // 33 93% 64% — variante clara del naranja
  );
  static const gradientHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F1F17), Color(0xFF173E26)], // 142 50% 18%
  );

  // Shadows — sombras suaves sobre fondo blanco. Sustituyen los borders
  // explícitos en cards: la sombra crea la separación.
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x080F1F17), blurRadius: 24, offset: Offset(0, 8), spreadRadius: -6),
    BoxShadow(color: Color(0x050F1F17), blurRadius: 6, offset: Offset(0, 2), spreadRadius: -1),
  ];

  /// Sombra prominente para CTAs y cards "featured".
  static const List<BoxShadow> shadowElegant = [
    BoxShadow(color: Color(0x261F8A4C), blurRadius: 32, offset: Offset(0, 12), spreadRadius: -10),
    BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, 4), spreadRadius: -4),
  ];

  /// Glow alrededor de elementos seleccionados / activos.
  static const List<BoxShadow> shadowGlow = [
    BoxShadow(color: Color(0x1A32AE40), blurRadius: 0, spreadRadius: 1),
    BoxShadow(color: Color(0x4032AE40), blurRadius: 24, offset: Offset(0, 8), spreadRadius: -8),
  ];
}

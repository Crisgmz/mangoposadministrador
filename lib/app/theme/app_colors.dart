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

  // Verde MangoPOS — color de marca oficial.
  //
  // Vista Global v2 bajó el verde un escalón: el brillante #32AE40 competía
  // con el naranja de acento y con los estados (rojo/ámbar) en una pantalla
  // que es, sobre todo, un tablero de alertas. El bosque #2A8E37 deja que el
  // acento y la severidad manden, y el sidebar oscuro ancla la interfaz.
  static const primary = Color(0xFF2A8E37);

  /// Variante clara — el mismo verde llevado 18% hacia el blanco, que es la
  /// regla de aclarado que usan los avatares y los gradientes del diseño.
  static const primaryGlow = Color(0xFF50A25B);
  static const primaryForeground = background;

  // Naranja acento — color de marca oficial
  static const accent = Color(0xFFF7951A); // 33 93% 54%
  static const accentForeground = Color(0xFFFFFFFF);
  static const accentSoft = Color(0xFFFEF3E7); // 33 90% 95%

  // Secondary / muted — neutrales gris claro (mejor contraste sobre fondo blanco)
  static const secondary = Color(0xFFF1F5F2); // verde-gris muy pálido
  static const secondaryForeground = foreground;
  static const muted = Color(
    0xFFF4F4F5,
  ); // 240 5% 96% — gris neutro para inputs/chips
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

  // Sidebar — verde bosque. Es el ancla visual de la consola: al ser más
  // oscuro que el contenido, la navegación deja de disputarle atención a los
  // KPIs y a la bandeja de acción. El item activo usa overlay blanco
  // translúcido (patrón "on-primary") y una barra de acento a la izquierda.
  static const sidebarBackground = Color(0xFF1B5E34);
  static const sidebarForeground = Color(0xFFFFFFFF);
  static const sidebarPrimary = accent;
  static const sidebarPrimaryForeground = Color(0xFFFFFFFF);
  static const sidebarAccent = Color(0xFF14472A); // verde más oscuro (overlay)
  static const sidebarAccentForeground = Color(0xFFFFFFFF);
  static const sidebarBorder = Color(0xFF14472A);
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
    colors: [
      accent,
      Color(0xFFF8AC4E),
    ], // 33 93% 64% — variante clara del naranja
  );
  static const gradientHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F1F17), Color(0xFF173E26)], // 142 50% 18%
  );

  // Shadows — sombras suaves sobre fondo blanco. Sustituyen los borders
  // explícitos en cards: la sombra crea la separación.
  static const List<BoxShadow> shadowCard = [
    BoxShadow(
      color: Color(0x080F1F17),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -6,
    ),
    BoxShadow(
      color: Color(0x050F1F17),
      blurRadius: 6,
      offset: Offset(0, 2),
      spreadRadius: -1,
    ),
  ];

  /// Sombra prominente para CTAs y cards "featured".
  static const List<BoxShadow> shadowElegant = [
    BoxShadow(
      color: Color(0x261F8A4C),
      blurRadius: 32,
      offset: Offset(0, 12),
      spreadRadius: -10,
    ),
    BoxShadow(
      color: Color(0x12000000),
      blurRadius: 8,
      offset: Offset(0, 4),
      spreadRadius: -4,
    ),
  ];

  /// Glow alrededor de elementos seleccionados / activos.
  static const List<BoxShadow> shadowGlow = [
    BoxShadow(color: Color(0x1A2A8E37), blurRadius: 0, spreadRadius: 1),
    BoxShadow(
      color: Color(0x402A8E37),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -8,
    ),
  ];
}

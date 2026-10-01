import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Transición entre pantallas de la consola: fundido corto con un leve
/// desplazamiento hacia arriba.
///
/// Reemplaza la de la plataforma. En web sobre macOS Flutter usaba la de iOS
/// (deslizamiento lateral de ~400 ms con paralaje), pensada para apps de
/// teléfono con gesto de volver: en una consola de escritorio se sentía como
/// que cada click tardaba en responder.
class ConsolePageTransitionsBuilder extends PageTransitionsBuilder {
  const ConsolePageTransitionsBuilder();

  /// Todas las plataformas: la consola se usa en navegador de escritorio y de
  /// teléfono, y tiene que sentirse igual en los dos.
  static const PageTransitionsTheme theme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ConsolePageTransitionsBuilder(),
      TargetPlatform.iOS: ConsolePageTransitionsBuilder(),
      TargetPlatform.macOS: ConsolePageTransitionsBuilder(),
      TargetPlatform.windows: ConsolePageTransitionsBuilder(),
      TargetPlatform.linux: ConsolePageTransitionsBuilder(),
      TargetPlatform.fuchsia: ConsolePageTransitionsBuilder(),
    },
  );

  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);

  /// Volver (p. ej. del detalle de un negocio al listado) es aún más corto:
  /// la pantalla de abajo ya está construida.
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 110);

  static final Animatable<double> _fade = CurveTween(curve: Curves.easeOut);

  static final Animatable<Offset> _rise = Tween<Offset>(
    begin: const Offset(0, 0.012),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic));

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation.drive(_fade),
      child: SlideTransition(
        position: animation.drive(_rise),
        // Las páginas (`ContentArea`) no pintan fondo propio: sin esto la
        // pantalla anterior se ve a través de la nueva mientras entra y los
        // textos de las dos se superponen.
        child: ColoredBox(color: AppColors.background, child: child),
      ),
    );
  }
}

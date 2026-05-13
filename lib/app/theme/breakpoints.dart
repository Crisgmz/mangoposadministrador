import 'package:flutter/widgets.dart';

/// Breakpoints del PRD §8.
///
/// - `≥ 1024 px`: layout desktop (sidebar fijo + topbar).
/// - `< 1024 px`: layout móvil/tablet (bottom nav + topbar compacto).
class Breakpoints {
  Breakpoints._();

  static const double mobile = 0;
  static const double tablet = 640;
  static const double desktop = 1024;
  static const double wide = 1440;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < tablet;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= tablet && w < desktop;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;
}

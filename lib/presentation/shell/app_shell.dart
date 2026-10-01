import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/breakpoints.dart';
import 'bottom_nav.dart';
import 'sidebar.dart';
import 'topbar.dart';

/// Shell de la aplicación. Único responsable del layout responsive global:
/// - `≥ 1024 px`: sidebar fijo + topbar + contenido + scroll vertical.
/// - `< 1024 px`: topbar (con botón menú que abre Drawer) + contenido + bottom nav.
///
/// Nota: el contenido se centra a un `maxWidth` de 1600px para no estirarse
/// en monitores anchos (replica el `max-w-[1600px]` del prototipo).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).matchedLocation;
    final isDesktop = Breakpoints.isDesktop(context);

    if (isDesktop) {
      // ⌘K / Ctrl+K enfoca el buscador global. Va acá y no en el topbar
      // porque un atajo solo dispara si el foco está dentro del subárbol que
      // lo registra — y el foco casi siempre está en el contenido.
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              ref.read(topbarSearchFocusProvider).requestFocus(),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              ref.read(topbarSearchFocusProvider).requestFocus(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              // En desktop el SafeArea solo importa para MacBooks con notch (Studio Display, etc).
              bottom: false,
              child: Row(
                children: [
                  Sidebar(currentPath: currentPath),
                  Expanded(
                    child: Column(
                      children: [
                        const Topbar(),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // < 1024 px → drawer + bottom nav
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: Drawer(
        backgroundColor: AppColors.sidebarBackground,
        child: Sidebar(currentPath: currentPath),
      ),
      body: SafeArea(
        // El BottomNav ya maneja su propio bottom inset.
        bottom: false,
        child: Builder(
          builder: (context) {
            return Column(
              children: [
                Topbar(onMenuTap: () => Scaffold.of(context).openDrawer()),
                Expanded(child: child),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNav(currentPath: currentPath),
    );
  }
}

class ContentArea extends StatelessWidget {
  const ContentArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.isDesktop(context);
    final isMobile = Breakpoints.isMobile(context);

    final hPad = isDesktop ? 40.0 : (isMobile ? 16.0 : 24.0);
    final vPad = isMobile ? 20.0 : 28.0;

    return SizedBox.expand(
      child: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1600),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

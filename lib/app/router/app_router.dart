import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_state.dart';
import '../../presentation/alerts/alerts_page.dart';
import '../../presentation/audit/audit_page.dart';
import '../../presentation/billing/billing_page.dart';
import '../../presentation/businesses/business_detail_page.dart';
import '../../presentation/businesses/businesses_page.dart';
import '../../presentation/cash/cash_health_page.dart';
import '../../presentation/cash/cash_session_detail_page.dart';
import '../../presentation/dashboard/dashboard_page.dart';
import '../../presentation/incidents/incidents_page.dart';
import '../../presentation/infrastructure/infrastructure_page.dart';
import '../../presentation/pending/pending_accounts_page.dart';
import '../../presentation/plans/plans_page.dart';
import '../../presentation/settings/settings_page.dart';
import '../../presentation/tables/tables_health_page.dart';
import '../../presentation/fiscal/fiscal_page.dart';
import '../../presentation/login/change_password_page.dart';
import '../../presentation/login/login_page.dart';
import '../../presentation/printing/printing_page.dart';
import '../../presentation/shell/app_shell.dart';
import '../../presentation/shell/placeholder_page.dart';

/// Listenable que dispara `notifyListeners()` cada vez que cambia el estado
/// de auth. Permite que GoRouter re-evalúe `redirect`.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _sub = ref.listen<AsyncValue<dynamic>>(
      authStateProvider,
      (_, _) => notifyListeners(),
      fireImmediately: false,
    );
  }

  late final ProviderSubscription _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final loggedIn = ref.read(isAuthenticatedProvider);
      final goingToLogin = state.matchedLocation == '/login';
      final goingToForbidden = state.matchedLocation == '/forbidden';

      if (!loggedIn) {
        return goingToLogin ? null : '/login';
      }

      // Autenticado pero todavía no sabemos si es operador.
      // El check vivo se hace dentro del shell (con loader) — aquí solo
      // redirigimos /login → / cuando ya hay sesión.
      if (goingToLogin) return '/';
      if (goingToForbidden) return null;
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, _) => const LoginPage(),
      ),
      GoRoute(
        path: '/forbidden',
        builder: (_, _) => const ForbiddenPage(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          // Gates encadenados: operador → cambio de clave forzado → shell.
          return Consumer(
            builder: (context, ref, _) {
              final operatorAsync = ref.watch(isPlatformOperatorProvider);

              // Se observa ACÁ ARRIBA, antes de los returns de abajo, para que
              // su RPC salga junto con el del chequeo de operador. Observado
              // más abajo, recién arrancaba cuando el otro terminaba: dos
              // viajes al servidor en fila antes de pintar la primera pantalla.
              final mustChangeAsync = ref.watch(mustChangePasswordProvider);

              // Revalidación en caliente (el token se refresca solo cada
              // hora): si ya sabemos que es operador, se sigue mostrando la
              // consola en vez de tapar todo con el splash. Antes, cada
              // refresh de sesión parpadeaba la app entera.
              final known = operatorAsync.valueOrNull;
              if (operatorAsync.isLoading && known == null) {
                return const _SplashLoading();
              }
              if (operatorAsync.hasError && known == null) {
                // No se pudo VERIFICAR — no es lo mismo que estar bloqueado.
                return AccessCheckErrorPage(error: operatorAsync.error);
              }
              if (known != true) return const ForbiddenPage();

              // Mismo criterio para el flag de cambio de clave: solo tapa la
              // pantalla la PRIMERA vez; después se resuelve en segundo plano.
              // Si el RPC falla, se deja pasar (se reevalúa en el próximo
              // refresh) — es un chequeo secundario, no la puerta.
              final mustChange = mustChangeAsync.valueOrNull;
              if (mustChange == null && mustChangeAsync.isLoading) {
                return const _SplashLoading();
              }
              return mustChange == true
                  ? const ChangePasswordPage()
                  : AppShell(child: child);
            },
          );
        },
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const ContentArea(child: DashboardPage()),
          ),
          GoRoute(
            path: '/negocios',
            builder: (_, _) => const ContentArea(child: BusinessesPage()),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => ContentArea(
                  child: BusinessDetailPage(
                    businessId: state.pathParameters['id']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/cajas',
            builder: (_, _) => const ContentArea(child: CashHealthPage()),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => ContentArea(
                  child: CashSessionDetailPage(
                    sessionId: state.pathParameters['id']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/mesas',
            builder: (_, _) => const ContentArea(child: TablesHealthPage()),
          ),
          GoRoute(
            path: '/facturacion',
            builder: (_, _) => const ContentArea(child: BillingPage()),
          ),
          GoRoute(
            path: '/planes',
            builder: (_, _) => const ContentArea(child: PlansPage()),
          ),
          GoRoute(
            path: '/fiscal',
            builder: (_, _) => const ContentArea(child: FiscalPage()),
          ),
          GoRoute(
            path: '/impresion',
            builder: (_, _) => const ContentArea(child: PrintingPage()),
          ),
          GoRoute(
            path: '/auditoria',
            builder: (_, _) => const ContentArea(child: AuditPage()),
          ),
          GoRoute(
            path: '/alertas',
            builder: (_, _) => const ContentArea(child: AlertsPage()),
          ),
          GoRoute(
            path: '/incidentes',
            builder: (_, _) => const ContentArea(child: IncidentsPage()),
          ),
          GoRoute(
            path: '/configuracion',
            builder: (_, _) => const ContentArea(child: SettingsPage()),
          ),
          GoRoute(
            path: '/pendientes',
            builder: (_, _) => const ContentArea(child: PendingAccountsPage()),
          ),
          GoRoute(
            path: '/infraestructura',
            builder: (_, _) => const ContentArea(child: InfrastructurePage()),
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => PlaceholderPage(
      title: 'No encontrado',
      subtitle: 'La ruta ${state.uri.path} no existe.',
    ),
  );
});

class _SplashLoading extends StatelessWidget {
  const _SplashLoading();

  @override
  Widget build(BuildContext context) {
    // Pantalla minimalista mientras se resuelve isPlatformOperatorProvider.
    return const ColoredBox(
      color: Color(0xFFF5F3EE),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: _Spinner(),
        ),
      ),
    );
  }
}

class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctl,
      child: const DecoratedBox(
        decoration: ShapeDecoration(
          shape: CircleBorder(side: BorderSide(color: Color(0xFF1F8A4C), width: 2.5)),
        ),
      ),
    );
  }
}

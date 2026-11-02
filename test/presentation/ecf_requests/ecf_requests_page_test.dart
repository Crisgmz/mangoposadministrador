// Bandeja de facturación electrónica de negocios nuevos.
// Lo que protege: que las solicitudes de MangoPOS y de Busi Pos Web salgan en
// una sola lista ordenada, que lo ya resuelto no ensucie la bandeja, que un
// origen caído no se lleve al otro, y que cada fila abra lo que le toca.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mangopos_administrador/app/widgets/nav_badges.dart';
import 'package:mangopos_administrador/app/widgets/nav_items.dart';
import 'package:mangopos_administrador/data/repositories/ecf_onboarding_repository.dart';
import 'package:mangopos_administrador/data/repositories/external_ecf_requests_repository.dart';
import 'package:mangopos_administrador/domain/models/ecf_onboarding.dart';
import 'package:mangopos_administrador/domain/models/external_ecf_request.dart';
import 'package:mangopos_administrador/presentation/ecf_requests/ecf_requests_page.dart';

EcfRequestSummary _pos(String id, String stage, String requestedAt) => EcfRequestSummary.fromJson({
      'business_id': id,
      'business_name': 'Negocio $id',
      'rnc': '131831151',
      'stage': stage,
      'requested_at': requestedAt,
    });

ExternalEcfRequest _ext(String id, String status, {bool registered = true, String? requestedAt}) =>
    ExternalEcfRequest.fromJson({
      'id': id,
      'source': 'flutter_shop+',
      'external_id': 'c-$id',
      'company_name': 'Empresa $id',
      'status': status,
      'company_registered': registered,
      'requested_at': requestedAt,
      'received_at': '2026-10-01T10:00:00Z',
    });

final _posRequests = [
  _pos('a', 'company', '2026-10-02T10:00:00Z'),
  _pos('b', 'active', '2026-09-01T10:00:00Z'),
];

final _externalRequests = [
  _ext('x', 'new', registered: false, requestedAt: '2026-10-03T10:00:00Z'),
  _ext('y', 'done', requestedAt: '2026-09-20T10:00:00Z'),
];

Future<void> _pump(
  WidgetTester tester, {
  Future<List<EcfRequestSummary>> Function()? pos,
  Future<List<ExternalEcfRequest>> Function()? external,
}) async {
  tester.view.physicalSize = const Size(1100, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const Scaffold(body: SingleChildScrollView(child: EcfRequestsPage()))),
    GoRoute(path: '/negocios/:id', builder: (_, s) => Scaffold(body: Text('Detalle ${s.pathParameters['id']}'))),
    GoRoute(
      path: '/facturacion-electronica/externa/:id',
      builder: (_, s) => Scaffold(body: Text('Alta externa ${s.pathParameters['id']}')),
    ),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ecfRequestsProvider.overrideWith((ref) => (pos ?? () async => _posRequests)()),
        externalEcfRequestsProvider.overrideWith((ref) => (external ?? () async => _externalRequests)()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('es', null));

  testWidgets('una sola lista, la más nueva primero, sin lo ya resuelto', (tester) async {
    await _pump(tester);

    expect(find.text('Empresa x'), findsOneWidget);
    expect(find.text('Negocio a'), findsOneWidget);
    expect(find.text('Negocio b'), findsNothing); // ya emite
    expect(find.text('Empresa y'), findsNothing); // atendida
    expect(tester.getTopLeft(find.text('Empresa x')).dy, lessThan(tester.getTopLeft(find.text('Negocio a')).dy));
    expect(find.text('Sin registrar'), findsOneWidget);
    expect(find.text('Falta registrar la empresa'), findsOneWidget);
    expect(find.text('Todas (2)'), findsOneWidget);
    expect(find.text('Busi Pos Web (1)'), findsOneWidget);
    expect(find.text('MangoPOS (1)'), findsOneWidget);
    expect(find.textContaining('1 de Busi Pos Web sin registrar en Alanube'), findsOneWidget);
  });

  testWidgets('filtra por origen y muestra todo al quitar "Solo pendientes"', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Busi Pos Web (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Empresa x'), findsOneWidget);
    expect(find.text('Negocio a'), findsNothing);

    await tester.tap(find.text('Solo pendientes'));
    await tester.pumpAndSettle();
    expect(find.text('Empresa y'), findsOneWidget);
    expect(find.text('Atendida'), findsOneWidget);

    await tester.tap(find.text('Todas (4)'));
    await tester.pumpAndSettle();
    expect(find.text('Negocio b'), findsOneWidget);
  });

  testWidgets('si un origen falla, el otro se sigue viendo', (tester) async {
    await _pump(tester, external: () async => throw Exception('relation does not exist'));

    expect(find.text('Negocio a'), findsOneWidget);
    expect(find.textContaining('No se pudieron leer las solicitudes de Busi Pos Web'), findsOneWidget);
  });

  testWidgets('MangoPOS abre el negocio; Busi Pos Web abre su página de alta', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Empresa x'));
    await tester.pumpAndSettle();
    expect(find.text('Alta externa x'), findsOneWidget);
  });

  testWidgets('MangoPOS abre el detalle del negocio', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Negocio a'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle a'), findsOneWidget);
  });

  test('el badge del menú cuenta las pendientes de los dos orígenes', () async {
    final container = ProviderContainer(overrides: [
      ecfRequestsProvider.overrideWith((ref) async => _posRequests),
      externalEcfRequestsProvider.overrideWith((ref) async => _externalRequests),
    ]);
    addTearDown(container.dispose);
    expect(container.read(navBadgeCountProvider(NavBadge.ecfRequests)), isNull);
    await container.read(ecfRequestsProvider.future);
    await container.read(externalEcfRequestsProvider.future);
    expect(container.read(navBadgeCountProvider(NavBadge.ecfRequests)), 2);
  });
}

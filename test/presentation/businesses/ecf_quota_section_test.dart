// Facturas electrónicas incluidas por negocio: ver el uso, fijar la cantidad,
// cambiar a precio propio y quitarla.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mangopos_administrador/data/repositories/ecf_quota_repository.dart';
import 'package:mangopos_administrador/domain/models/ecf_quota_usage.dart';
import 'package:mangopos_administrador/presentation/businesses/ecf_quota_section.dart';

final _noQuota = EcfQuotaUsage.fromJson({
  'has_quota': false,
  'global_price_cents': 1500,
  'unit_price_cents': 1500,
  'current': {'has_quota': false, 'overage_cents': 0},
  'last_30_days': 37,
  'history': [],
});

final _withExtra = EcfQuotaUsage.fromJson({
  'has_quota': true,
  'included': 5,
  'global_price_cents': 1500,
  'unit_price_cents': 1500,
  'counting_since': '2026-09-01T04:00:00Z',
  'next_charge_date': '2026-10-16',
  'current': {
    'has_quota': true,
    'used': 9,
    'extra': 4,
    'overage_cents': 6000,
    'usage_from': '2026-09-16T12:00:00Z',
    'usage_to': '2026-09-18T04:00:00Z',
  },
  'last_30_days': 9,
  'history': [],
});

class _FakeRepo extends EcfQuotaRepository {
  _FakeRepo(this._usage)
    : super(
        SupabaseClient(
          'http://localhost',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  EcfQuotaUsage _usage;
  final setCalls = <({int included, int? price, String? notes})>[];
  var clearCalls = 0;

  @override
  Future<EcfQuotaUsage> get(String businessId) async => _usage;

  @override
  Future<EcfQuotaUsage> set({
    required String businessId,
    required int included,
    int? priceOverrideCents,
    String? notes,
  }) async {
    setCalls.add((included: included, price: priceOverrideCents, notes: notes));
    _usage = EcfQuotaUsage.fromJson({
      'has_quota': true,
      'included': included,
      'price_override_cents': priceOverrideCents,
      'global_price_cents': 1500,
      'unit_price_cents': priceOverrideCents ?? 1500,
      'current': {'has_quota': true, 'used': 0, 'extra': 0, 'overage_cents': 0},
      'last_30_days': 0,
      'history': [],
    });
    return _usage;
  }

  @override
  Future<EcfQuotaUsage> clear(String businessId) async {
    clearCalls++;
    _usage = _noQuota;
    return _usage;
  }
}

Future<_FakeRepo> _pump(WidgetTester tester, EcfQuotaUsage initial) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = _FakeRepo(initial);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ecfQuotaRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: EcfQuotaSection(
              businessId: 'b-maison',
              businessName: 'La Maison Francaise',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('sin cantidad: se establece desde la sección', (tester) async {
    final repo = await _pump(tester, _noQuota);

    expect(find.textContaining('Sin cantidad configurada'), findsOneWidget);
    expect(find.textContaining('últimos 30 días: 37'), findsOneWidget);

    await tester.tap(find.text('Establecer cantidad'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Se empiezan a contar desde que guardes'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Incluidas por período'),
      '500',
    );
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(repo.setCalls.single.included, 500);
    expect(repo.setCalls.single.price, isNull);
    expect(
      find.text('Cantidad de facturas electrónicas guardada.'),
      findsOneWidget,
    );
    expect(find.text('500'), findsOneWidget);
    expect(find.text('Quitar cantidad'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con extra: muestra el uso y cambia a precio propio', (
    tester,
  ) async {
    final repo = await _pump(tester, _withExtra);

    expect(find.textContaining('9 de 5'), findsOneWidget);
    expect(find.text('RD\$ 15.00 (precio global)'), findsOneWidget);
    expect(find.text('4 × RD\$ 15.00 = RD\$ 60.00'), findsOneWidget);
    expect(find.text('Se suma al próximo cobro (16/10/2026).'), findsOneWidget);

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    // Sin precio propio no hay campo de precio hasta apagar "precio global".
    expect(
      find.widgetWithText(TextField, 'Precio por factura extra'),
      findsNothing,
    );
    await tester.tap(find.text('Usar el precio global'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Precio por factura extra'),
      '20',
    );
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(repo.setCalls.single.included, 5);
    expect(repo.setCalls.single.price, 2000);
    expect(find.text('RD\$ 20.00 (precio propio)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quitar la cantidad pide confirmación', (tester) async {
    final repo = await _pump(tester, _withExtra);

    await tester.tap(find.text('Quitar cantidad'));
    await tester.pumpAndSettle();
    expect(find.textContaining('dejarán de cobrarse aparte'), findsOneWidget);
    expect(repo.clearCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Quitar'));
    await tester.pumpAndSettle();

    expect(repo.clearCalls, 1);
    expect(find.textContaining('Sin cantidad configurada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

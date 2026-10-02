// Bloqueo por falta de pago: ver si está activo, a quién afectaría y encenderlo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mangopos_administrador/data/repositories/business_access_repository.dart';
import 'package:mangopos_administrador/domain/models/business_access.dart';
import 'package:mangopos_administrador/presentation/settings/access_policy_card.dart';

const _policyOff = AccessPolicy(
  enforcementEnabled: false,
  defaultGraceDays: 5,
  lockOnPastDue: true,
  lockOnTrialExpired: false,
  offlineMaxDays: 7,
);

final _affectedRows = [
  const AffectedBusiness(
    businessId: 'b1',
    businessName: 'La Maison Francaise',
    state: 'locked',
    reason: 'subscription_suspended',
    enforced: false,
    billingStatus: 'suspended',
  ),
  AffectedBusiness(
    businessId: 'b2',
    businessName: 'Tropella Coffee',
    state: 'grace',
    reason: 'payment_overdue',
    enforced: false,
    graceEndsAt: DateTime(2026, 10, 5),
  ),
];

class _FakeRepo extends BusinessAccessRepository {
  _FakeRepo({
    AccessPolicy policy = _policyOff,
    List<AffectedBusiness>? affected,
  }) : _policy = policy,
       _rows = affected ?? _affectedRows,
       super(
         SupabaseClient(
           'http://localhost',
           'anon',
           authOptions: const AuthClientOptions(autoRefreshToken: false),
         ),
       );

  AccessPolicy _policy;
  final List<AffectedBusiness> _rows;
  final setCalls = <({bool? enforcement, int? grace, String reason})>[];

  @override
  Future<AccessPolicy?> getPolicy() async => _policy;

  @override
  Future<List<AffectedBusiness>> listAffected() async => _rows;

  @override
  Future<AccessPolicy?> setPolicy({
    required String reason,
    bool? enforcementEnabled,
    int? defaultGraceDays,
    bool? lockOnPastDue,
    bool? lockOnTrialExpired,
    int? offlineMaxDays,
    String? defaultCustomerMessage,
    String? contactName,
    String? contactPhone,
    String? contactEmail,
  }) async {
    setCalls.add((
      enforcement: enforcementEnabled,
      grace: defaultGraceDays,
      reason: reason,
    ));
    _policy = AccessPolicy(
      enforcementEnabled: enforcementEnabled ?? _policy.enforcementEnabled,
      defaultGraceDays: defaultGraceDays ?? _policy.defaultGraceDays,
      lockOnPastDue: lockOnPastDue ?? _policy.lockOnPastDue,
      lockOnTrialExpired: lockOnTrialExpired ?? _policy.lockOnTrialExpired,
      offlineMaxDays: _policy.offlineMaxDays,
    );
    return _policy;
  }
}

Future<_FakeRepo> _pump(WidgetTester tester, {_FakeRepo? repo}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final r = repo ?? _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [businessAccessRepositoryProvider.overrideWithValue(r)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: AccessPolicyCard(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return r;
}

void main() {
  testWidgets('apagado: muestra a quién bloquearía al encenderlo', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('APAGADO'), findsOneWidget);
    expect(
      find.text('Si lo enciendes, hoy quedarían bloqueados: 1'),
      findsOneWidget,
    );
    expect(find.text('En gracia: 1 · Con aviso: 0'), findsOneWidget);
    expect(
      find.text('La Maison Francaise · suscripción suspendida · suspended'),
      findsOneWidget,
    );
    expect(find.textContaining('el más próximo: 05/10/2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('encender pide razón y queda activo', (tester) async {
    final repo = await _pump(tester);

    // Sin cambios, no hay nada que guardar.
    final before = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Guardar cambios'),
    );
    expect(before.onPressed, isNull);

    await tester.tap(find.text('Aplicar bloqueos automáticamente'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar cambios'));
    await tester.pumpAndSettle();

    expect(find.text('Encender el bloqueo automático'), findsOneWidget);
    expect(find.textContaining('apenas inician sesión'), findsOneWidget);
    expect(repo.setCalls, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Encender'));
    await tester.pumpAndSettle();

    expect(repo.setCalls.single.enforcement, isTrue);
    expect(repo.setCalls.single.reason, 'Activación del bloqueo automático');
    expect(find.text('ACTIVO'), findsOneWidget);
    expect(
      find.text('Bloqueo automático activo: se aplica al iniciar sesión.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cambiar los días de gracia se guarda con su razón', (
    tester,
  ) async {
    final repo = await _pump(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Días de gracia'),
      '10',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar cambios'));
    await tester.pumpAndSettle();

    expect(find.text('Guardar política de bloqueo'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(repo.setCalls.single.grace, 10);
    expect(repo.setCalls.single.enforcement, isFalse);
    expect(repo.setCalls.single.reason, 'Ajuste de política de bloqueo');
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangopos_administrador/presentation/shared/deferred_section.dart';

void main() {
  Widget host() => const MaterialApp(
    home: Column(
      children: [
        DeferredSection(
          frames: 1,
          placeholderHeight: 40,
          child: Text('primera'),
        ),
        DeferredSection(
          frames: 3,
          placeholderHeight: 60,
          child: Text('tercera'),
        ),
      ],
    ),
  );

  testWidgets('no construye nada en el primer frame', (tester) async {
    await tester.pumpWidget(host());

    expect(find.text('primera'), findsNothing);
    expect(find.text('tercera'), findsNothing);
    // Mientras tanto reserva el alto indicado.
    expect(tester.getSize(find.byType(SizedBox).first).height, 40);
  });

  testWidgets('escalona: cada sección entra en su frame', (tester) async {
    await tester.pumpWidget(host());

    await tester.pump();
    expect(find.text('primera'), findsOneWidget);
    expect(find.text('tercera'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('primera'), findsOneWidget);
    expect(find.text('tercera'), findsOneWidget);
  });

  testWidgets('desmontar antes de tiempo no falla', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpWidget(const SizedBox());

    // Si el estado siguiera esperando frames y llamara setState después de
    // dispose, esto lanza.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

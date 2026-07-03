import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:preguntas_ui/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Loads the first question and allows free navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const PreguntasApp());
    // The questions asset is read via real (non-fake) IO, so it needs runAsync to resolve.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('Según el apartado 1, ¿qué establece la presente Norma Foral?'), findsOneWidget);
    expect(find.text('Pregunta 1 / 290'), findsOneWidget);

    // "Anterior" is disabled on the first question.
    final previousButton = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Anterior'));
    expect(previousButton.onPressed, isNull);

    // Answering doesn't lock navigation: "Siguiente" is available before and after answering.
    await tester.tap(find.text(
      'Los principios y las normas jurídicas generales del sistema tributario del Territorio Histórico de Bizkaia.',
    ));
    await tester.pump();

    await tester.tap(find.text('Siguiente'));
    await tester.pump();

    expect(find.text('Pregunta 2 / 290'), findsOneWidget);

    await tester.tap(find.text('Anterior'));
    await tester.pump();

    expect(find.text('Pregunta 1 / 290'), findsOneWidget);
  });
}

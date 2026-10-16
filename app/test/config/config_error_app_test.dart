import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/config/config_error_app.dart';

void main() {
  testWidgets('says the configuration could not load', (tester) async {
    await tester.pumpWidget(const ConfigErrorApp());
    expect(
      find.text(
        'Não foi possível carregar a configuração. Tente de novo em alguns minutos.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('meets the text contrast guideline', (tester) async {
    await tester.pumpWidget(const ConfigErrorApp());
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('does not overflow at 200% text on a phone', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const ConfigErrorApp());
    expect(tester.takeException(), isNull);
  });
}

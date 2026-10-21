import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';

import '../family/widgets_test.dart' show pumpIn;

void main() {
  testWidgets('names its steps with the word it is given, one module per '
      'step, filled up to the current one', (tester) async {
    await pumpIn(tester, const StepMarks(step: 2, of: 5, word: 'Etapa'));

    expect(find.text('Etapa 2 de 5'), findsOneWidget);
    final modules = tester
        .widgetList<StateModule>(find.byType(StateModule))
        .toList();
    expect(modules, hasLength(5));
    expect(modules.where((m) => m.filled), hasLength(2));
  });

  testWidgets('says "Passo" unless told otherwise', (tester) async {
    await pumpIn(tester, const StepMarks(step: 1, of: 2));

    expect(find.text('Passo 1 de 2'), findsOneWidget);
  });
}

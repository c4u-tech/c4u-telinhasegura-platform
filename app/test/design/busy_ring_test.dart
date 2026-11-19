import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/busy_ring.dart';
import 'package:telinha_segura/family/widgets.dart';

import 'pump.dart';

/// Every busy indicator: a spinning ring, or a still partial ring where
/// the platform asks for less motion, read the same either way.
void main() {
  final busy = <String, Widget>{
    'the primary action': PrimaryButton(
      label: 'Entrar',
      onPressed: () {},
      busy: true,
    ),
    'a quiet action': QuietAction(
      label: 'Reenviar',
      onPressed: () {},
      busy: true,
    ),
    'a door row': DoorRow(title: 'Lia', onTap: () {}, busy: true),
  };

  CircularProgressIndicator ring(WidgetTester tester) =>
      tester.widget(find.byType(CircularProgressIndicator));

  SemanticsData read(WidgetTester tester) => tester
      .getSemantics(find.byType(CircularProgressIndicator))
      .getSemanticsData();

  for (final MapEntry(key: name, value: control) in busy.entries) {
    testWidgets('$name spins while busy', (tester) async {
      await pumpOn(tester, control);
      expect(find.byType(BusyRing), findsOneWidget);
      expect(ring(tester).value, isNull);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('$name shows a still partial ring under reduced motion, '
        'read as before', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpOn(tester, control);
      final spinning = read(tester);

      await tester.pumpWidget(const SizedBox());
      await pumpOn(tester, control, disableAnimations: true);
      final value = ring(tester).value;
      expect(value, isNotNull);
      expect(value, inExclusiveRange(0, 1), reason: 'a partial ring');
      expect(tester.binding.transientCallbackCount, 0, reason: 'still');
      final still = read(tester);
      expect(still.label, spinning.label);
      expect(still.value, spinning.value);
      expect(still.role, spinning.role);
      expect(still.flagsCollection, spinning.flagsCollection);
      handle.dispose();
    });
  }

  test('no screen draws a spinner of its own', () {
    final bare = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.endsWith('busy_ring.dart') &&
            file.readAsStringSync().contains('CircularProgressIndicator('))
          file.path,
    ];
    expect(bare, isEmpty);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/answer_choice.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/profile_fields.dart';
import 'package:telinha_segura/kid_mode/hand_over_screen.dart';

import 'pump.dart';

/// The guardian's controls that fill or ring as they change: each eases
/// over the scale's change, and is a cut when the platform asks for less
/// motion.
void main() {
  final controls = <String, Widget>{
    'an answer key': AnswerChoice(
      question: 'Tem violência?',
      value: null,
      onChanged: (_) {},
    ),
    'a state module': const StateModule(filled: true),
    'a child to hand over to': ChildChoice(
      nickname: 'Lia',
      avatar: Avatar.values.first,
      selected: false,
      onTap: () {},
    ),
    'an avatar': AvatarPicker(value: null, onChanged: (_) {}),
    'a selectable row': SelectableRow(
      label: 'Mais 15 min',
      selected: false,
      onTap: () {},
    ),
  };

  List<Duration> durations(WidgetTester tester) => [
    for (final c in tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    ))
      c.duration,
  ];

  for (final MapEntry(key: name, value: control) in controls.entries) {
    testWidgets('$name eases over the scale\'s change', (tester) async {
      await pumpOn(tester, control);
      final all = durations(tester);
      expect(all, isNotEmpty);
      expect(all, everyElement(Motion.change));
    });

    testWidgets('$name is a cut under reduced motion', (tester) async {
      await pumpOn(tester, control, disableAnimations: true);
      final all = durations(tester);
      expect(all, isNotEmpty);
      expect(all, everyElement(Duration.zero));
    });
  }
}

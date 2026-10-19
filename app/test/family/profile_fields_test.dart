import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/labels.dart';
import 'package:telinha_segura/family/profile_fields.dart';

import 'widgets_test.dart' show pumpIn;

void main() {
  group('nickname', () {
    test('is 1 to 20 characters after trimming', () {
      expect(nicknameOf(''), isNull);
      expect(nicknameOf('   '), isNull);
      expect(nicknameOf('  Lia '), 'Lia');
      expect(nicknameOf('a' * 20), 'a' * 20);
      expect(nicknameOf('a' * 21), isNull);
      // Counted in code points, as the server counts runes.
      expect(nicknameOf('ã' * 20), 'ã' * 20);
    });

    testWidgets('the guidance module fills once the nickname fits', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpIn(tester, NicknameField(controller: controller));

      expect(find.text(nicknameGuidance), findsOneWidget);
      expect(
        tester.widget<StateModule>(find.byType(StateModule)).filled,
        false,
      );

      await tester.enterText(find.byType(TextField), 'Lia');
      await tester.pump();
      expect(tester.widget<StateModule>(find.byType(StateModule)).filled, true);

      await tester.enterText(find.byType(TextField), 'a' * 21);
      await tester.pump();
      expect(
        tester.widget<StateModule>(find.byType(StateModule)).filled,
        false,
      );
    });

    testWidgets('wrapped at 200% text, the guidance module sits on its '
        'first line', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpIn(tester, NicknameField(controller: controller), textScale: 2);

      final words = find.text(nicknameGuidance);
      final line = tester
          .renderObject<RenderParagraph>(words)
          .getFullHeightForCaret(const TextPosition(offset: 0));
      expect(tester.getSize(words).height, greaterThan(line * 1.5));
      expect(
        tester.getCenter(find.byType(StateModule)).dy,
        moreOrLessEquals(tester.getTopLeft(words).dy + line / 2, epsilon: 1),
      );
    });
  });

  group('AvatarPicker', () {
    testWidgets('offers the twelve animals, none chosen yet', (tester) async {
      await pumpIn(tester, AvatarPicker(value: null, onChanged: (_) {}));

      final discs = tester.widgetList<AvatarDisc>(find.byType(AvatarDisc));
      expect(
        discs.map((d) => d.avatar),
        Avatar.values.where((a) => a != Avatar.unknown),
      );
      // The ring and the radio semantics carry the choice: no wordless
      // modules under the animals.
      expect(find.byType(StateModule), findsNothing);
    });

    testWidgets('each animal is a labelled choice of one, 48 dp or more', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpIn(tester, AvatarPicker(value: Avatar.owl, onChanged: (_) {}));

      for (final avatar in Avatar.values.where((a) => a != Avatar.unknown)) {
        final label = find.bySemanticsLabel(avatar.label);
        expect(label, findsOneWidget, reason: avatar.label);
        expect(
          tester.getSemantics(label),
          isSemantics(
            label: avatar.label,
            hasCheckedState: true,
            isChecked: avatar == Avatar.owl,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true,
          ),
        );
        final size = tester.getSize(find.byKey(ValueKey(avatar)));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('a tap chooses, and the chosen one takes the 3 px ring', (
      tester,
    ) async {
      Avatar? chosen;
      await pumpIn(
        tester,
        StatefulBuilder(
          builder: (context, setState) => AvatarPicker(
            value: chosen,
            onChanged: (a) => setState(() => chosen = a),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey(Avatar.frog)));
      await tester.pump();

      expect(chosen, Avatar.frog);
      BorderSide ringOf(Avatar avatar) {
        final ring = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(ValueKey(avatar)),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return ((ring.decoration! as ShapeDecoration).shape as CircleBorder)
            .side;
      }

      expect(ringOf(Avatar.frog).width, 3);
      expect(ringOf(Avatar.frog).color, isNot(Colors.transparent));
      expect(ringOf(Avatar.fox).color, Colors.transparent);
      expect(find.byType(StateModule), findsNothing);
    });

    testWidgets('fits four to a row on a phone column', (tester) async {
      await pumpIn(tester, AvatarPicker(value: null, onChanged: (_) {}));

      final tops = {
        for (final a in Avatar.values.where((a) => a != Avatar.unknown))
          tester.getTopLeft(find.byKey(ValueKey(a))).dy,
      };
      expect(tops, hasLength(3));
      expect(tester.takeException(), isNull);
    });
  });

  group('AgeBandChoice', () {
    testWidgets('three bands, none chosen yet', (tester) async {
      await pumpIn(tester, AgeBandChoice(value: null, onChanged: (_) {}));

      for (final band in [AgeBand.upTo4, AgeBand.from5To8, AgeBand.from9To12]) {
        expect(find.text(band.label), findsOneWidget);
      }
      expect(find.text(AgeBand.unknown.label), findsNothing);
      final modules = tester.widgetList<StateModule>(find.byType(StateModule));
      expect(modules.where((m) => m.filled), isEmpty);
    });

    testWidgets('a tap chooses; each row is a labelled choice of one', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      AgeBand? chosen;
      await pumpIn(
        tester,
        StatefulBuilder(
          builder: (context, setState) => AgeBandChoice(
            value: chosen,
            onChanged: (b) => setState(() => chosen = b),
          ),
        ),
      );

      await tester.tap(find.text(AgeBand.from9To12.label));
      await tester.pump();

      expect(chosen, AgeBand.from9To12);
      expect(
        tester.getSemantics(find.bySemanticsLabel(AgeBand.from9To12.label)),
        isSemantics(
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(AgeBand.upTo4.label)),
        isSemantics(hasCheckedState: true, isChecked: false),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('on a child\'s profile, "2 a 4 anos" chosen shows the advice '
        'about children under 2; another band hides it', (tester) async {
      AgeBand? chosen;
      await pumpIn(
        tester,
        StatefulBuilder(
          builder: (context, setState) => AgeBandChoice(
            value: chosen,
            adviseUnderTwo: true,
            onChanged: (b) => setState(() => chosen = b),
          ),
        ),
      );
      expect(find.text(underTwoAdvice), findsNothing);

      await tester.tap(find.text('2 a 4 anos'));
      await tester.pump();
      expect(find.text(underTwoAdvice), findsOneWidget);

      await tester.tap(find.text('5 a 8 anos'));
      await tester.pump();
      expect(find.text(underTwoAdvice), findsNothing);
    });

    testWidgets('without the advice asked for, "2 a 4 anos" shows none', (
      tester,
    ) async {
      await pumpIn(
        tester,
        AgeBandChoice(value: AgeBand.upTo4, onChanged: (_) {}),
      );
      expect(find.text(underTwoAdvice), findsNothing);
    });
  });

  for (final height in [56.0, 64.0]) {
    testWidgets('a ${height.toInt()} dp row holds its label and module still '
        'as the stroke thickens on choosing', (tester) async {
      Future<(Rect, Rect)> boxes(bool selected) async {
        await pumpIn(
          tester,
          SelectableRow(
            label: 'Mais 15 min',
            selected: selected,
            onTap: () {},
            height: height,
          ),
        );
        await tester.pumpAndSettle();
        return (
          tester.getRect(find.text('Mais 15 min')),
          tester.getRect(find.byType(StateModule)),
        );
      }

      final idle = await boxes(false);
      final chosen = await boxes(true);
      expect(chosen, idle);
    });
  }
}

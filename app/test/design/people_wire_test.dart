import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/people_wire.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/tokens.dart';

import 'pump.dart';

PeopleWirePainter painterOf(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(PeopleWire),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as PeopleWirePainter;

void main() {
  group('the mascot in one colour', () {
    final figure = TeviPainter.oneColour;

    test('keeps the crown, the pupil, the body below the eyebrow, the '
        'tail, both legs and the whole beak', () {
      for (final p in const [
        Offset(56, 30), // crown
        Offset(77, 52), // pupil
        Offset(40, 70), // lower body
        Offset(108, 55), // beak
        Offset(8, 76), // tail
        Offset(44, 98), // front leg
        Offset(62, 98), // back leg
      ]) {
        expect(figure.contains(p), isTrue, reason: '$p');
      }
    });

    test('runs the beak straight out of the body, with no gap before it', () {
      for (var x = 96.0; x <= 104; x += .5) {
        expect(figure.contains(Offset(x, 55)), isTrue, reason: 'x $x');
      }
    });

    test('opens the eyebrow and the eye around the pupil to the ground, '
        'and the air between the legs', () {
      for (final p in const [
        Offset(30, 41), // eyebrow
        Offset(96, 41), // eyebrow, over the beak's root
        Offset(66, 52), // the eye, outside the pupil
        Offset(53, 98), // between the legs
      ]) {
        expect(figure.contains(p), isFalse, reason: '$p');
      }
    });
  });

  group('the wire of people', () {
    testWidgets('draws one bird per person', (tester) async {
      await pumpOn(tester, const PeopleWire(people: 3));

      expect(painterOf(tester).birds, 3);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('five birds at most; the rest as "+N" beside them', (
      tester,
    ) async {
      await pumpOn(tester, const PeopleWire(people: 12));

      expect(painterOf(tester).birds, 5);
      expect(find.text('+7'), findsOneWidget);
      final wire = tester.getRect(find.byType(PeopleWire));
      final more = tester.getRect(find.text('+7'));
      expect(more.left, greaterThan(wire.left + painterOf(tester).birdsWidth));
    });

    testWidgets('exactly five has no remainder', (tester) async {
      await pumpOn(tester, const PeopleWire(people: 5));

      expect(painterOf(tester).birds, 5);
      expect(find.textContaining('+'), findsNothing);
    });

    for (final ground in [Ground.light, Ground.dark]) {
      testWidgets('in the text colour, about 40 dp tall (${ground.name})', (
        tester,
      ) async {
        await pumpOn(tester, const PeopleWire(people: 12), ground: ground);
        final palette = ground == Ground.light ? Palette.light : Palette.dark;

        expect(painterOf(tester).color, palette.text);
        expect(tester.widget<Text>(find.text('+7')).style?.color, palette.text);
        expect(tester.getSize(find.byType(PeopleWire)).height, 40);
      });
    }

    test('each bird sits on the wire, its body\'s foot in the line', () {
      const painter = PeopleWirePainter(birds: 5, color: Color(0xFF000000));
      for (var i = 0; i < 5; i++) {
        final x = painter.footAt(i);
        expect(
          (painter.bodyBottom(i, 320) - PeopleWirePainter.wireAt(x, 320)).abs(),
          lessThanOrEqualTo(PeopleWirePainter.stroke / 2),
          reason: 'bird $i',
        );
      }
    });

    testWidgets('the birds stay smaller than the mascot at its smallest', (
      tester,
    ) async {
      await pumpOn(tester, const PeopleWire(people: 1));

      expect(painterOf(tester).birdHeight, lessThan(32));
    });

    testWidgets('is decoration: nothing of it reaches the screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpOn(tester, const PeopleWire(people: 12));

      expect(semanticsStrings(tester), isNot(contains('+7')));
      semantics.dispose();
    });

    testWidgets('at 200 % text the remainder still fits beside the birds', (
      tester,
    ) async {
      await pumpOn(tester, const PeopleWire(people: 12), textScale: 2);

      expect(tester.takeException(), isNull);
      expect(find.text('+7'), findsOneWidget);
    });
  });
}

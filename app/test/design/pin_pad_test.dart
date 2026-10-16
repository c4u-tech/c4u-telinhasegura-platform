import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/pin_pad.dart';
import 'package:telinha_segura/design/tokens.dart';

import 'pump.dart';
import 'tokens_test.dart' show contrast;

List<bool> modules(WidgetTester tester) => tester
    .widgetList<StateModule>(find.byType(StateModule))
    .map((m) => m.filled)
    .toList();

Future<void> press(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await tester.pump();
}

Future<void> type(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await press(tester, d);
  }
}

void expectEnabled(WidgetTester tester, String label, bool enabled) => expect(
  tester.getSemantics(find.bySemanticsLabel(label)),
  isSemantics(isEnabled: enabled),
  reason: label,
);

/// The key read by [label]: its button's material, as painted.
Material keyMaterial(WidgetTester tester, String label) =>
    tester.widget<Material>(
      find
          .descendant(
            of: find.bySemanticsLabel(label),
            matching: find.byType(Material),
          )
          .first,
    );

/// The size an action key's icon takes, and a digit key's type size.
(double, double) iconAndDigit(WidgetTester tester) => (
  tester.widget<Icon>(find.byIcon(Icons.arrow_forward_rounded)).size!,
  tester
      .renderObject<RenderParagraph>(find.text('5'))
      .textScaler
      .scale(
        tester.widget<Text>(find.text('5')).style?.fontSize ??
            DefaultTextStyle.of(tester.element(find.text('5'))).style.fontSize!,
      ),
);

void main() {
  testWidgets('each typed digit fills a module, never shows the digit', (
    tester,
  ) async {
    await pumpOn(tester, PinPad(onSubmit: (_) {}));
    expect(modules(tester), List.filled(6, false));

    await type(tester, '739');

    expect(modules(tester), [true, true, true, false, false, false]);
    // Only the keys' own faces: one "7", one "3", one "9".
    for (final d in '739'.split('')) {
      expect(find.text(d), findsOneWidget);
    }
    expect(find.textContaining('739'), findsNothing);
  });

  testWidgets('the module row reads the count only, and the tree never '
      'holds the digits', (tester) async {
    await pumpOn(tester, PinPad(onSubmit: (_) {}));
    await type(tester, '2580');

    expect(find.bySemanticsLabel('4 de 6 números digitados'), findsOneWidget);
    final allowed = {
      for (var d = 0; d <= 9; d++) '$d',
      'Apagar',
      'Confirmar',
      '4 de 6 números digitados',
    };
    expect(semanticsStrings(tester).toSet().difference(allowed), isEmpty);
  });

  testWidgets('confirm opens at 4 digits and submits the PIN', (tester) async {
    final submitted = <String>[];
    await pumpOn(tester, PinPad(onSubmit: submitted.add));

    await type(tester, '123');
    expectEnabled(tester, 'Confirmar', false);
    await press(tester, 'Confirmar');
    expect(submitted, isEmpty);

    await type(tester, '4');
    expectEnabled(tester, 'Confirmar', true);
    await press(tester, 'Confirmar');
    expect(submitted, ['1234']);
  });

  testWidgets('takes at most 6 digits; erase takes back the last', (
    tester,
  ) async {
    final submitted = <String>[];
    await pumpOn(tester, PinPad(onSubmit: submitted.add));

    await type(tester, '1234567');
    expect(modules(tester), List.filled(6, true));
    await press(tester, 'Apagar');
    expect(modules(tester).where((f) => f), hasLength(5));
    await press(tester, 'Confirmar');
    expect(submitted, ['12345']);
  });

  testWidgets('keyboard and hardware digits, Backspace and Enter work', (
    tester,
  ) async {
    final submitted = <String>[];
    await pumpOn(tester, PinPad(onSubmit: submitted.add));

    for (final key in [
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.digit9,
      LogicalKeyboardKey.digit9,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.numpad0,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pump();
    expect(modules(tester).where((f) => f), hasLength(4));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(submitted, ['4290']);
  });

  testWidgets('Enter before 4 digits submits nothing', (tester) async {
    final submitted = <String>[];
    await pumpOn(tester, PinPad(onSubmit: submitted.add));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    expect(submitted, isEmpty);
  });

  testWidgets('the parent clears it after a wrong PIN', (tester) async {
    final controller = PinPadController();
    addTearDown(controller.dispose);
    await pumpOn(tester, PinPad(controller: controller, onSubmit: (_) {}));
    await type(tester, '1111');

    controller.clear();
    await tester.pump();

    expect(modules(tester), List.filled(6, false));
    expect(find.bySemanticsLabel('0 de 6 números digitados'), findsOneWidget);
  });

  testWidgets('disabled (busy or cooling down), it takes no key at all', (
    tester,
  ) async {
    final submitted = <String>[];
    await pumpOn(tester, PinPad(enabled: false, onSubmit: submitted.add));

    await tester.tap(find.text('5'), warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pump();
    expect(modules(tester), List.filled(6, false));
    expectEnabled(tester, '5', false);
  });

  for (final ground in Ground.values) {
    testWidgets('on the ${ground.name} ground: 64 dp keys, labelled, '
        'readable', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpOn(tester, PinPad(onSubmit: (_) {}), ground: ground);
      await type(tester, '1234');

      for (final label in ['1', '0', 'Apagar', 'Confirmar']) {
        final size = tester.getSize(find.bySemanticsLabel(label));
        expect(size.width, greaterThanOrEqualTo(64), reason: label);
        expect(size.height, greaterThanOrEqualTo(64), reason: label);
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });
  }

  testWidgets('on ink the digits are the quiet keys and "Confirmar" the one '
      'filled cream key', (tester) async {
    const kid = Palette.kid;
    await pumpOn(tester, PinPad(onSubmit: (_) {}), ground: Ground.kid);

    // A digit: the night-input tone, a 1.5 px outline-tone stroke, cream.
    final digit = keyMaterial(tester, '5');
    expect(digit.color, kid.input);
    expect(digit.textStyle?.color, kid.text);
    final side = (digit.shape! as RoundedRectangleBorder).side;
    expect((side.color, side.width), (kid.outline, 1.5));
    expect(contrast(kid.text, kid.input), greaterThanOrEqualTo(4.5));
    expect(contrast(kid.outline, kid.ground), greaterThanOrEqualTo(3));
    expect(contrast(kid.outline, kid.input), greaterThanOrEqualTo(3));

    // Disabled confirm: the outline tone at 32%, its arrow at 60%.
    var confirm = keyMaterial(tester, 'Confirmar');
    expect(confirm.color, kid.outline.withValues(alpha: 0.32));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.arrow_forward_rounded)).color ??
          IconTheme.of(tester.element(find.byIcon(Icons.arrow_forward_rounded)))
              .color,
      kid.text.withValues(alpha: 0.6),
    );

    await type(tester, '1234');
    // The button eases its icon colour over the theme's animation.
    await tester.pumpAndSettle();
    confirm = keyMaterial(tester, 'Confirmar');
    expect(confirm.color, kid.action);
    expect((confirm.shape! as RoundedRectangleBorder).side, BorderSide.none);
    expect(
      IconTheme.of(tester.element(find.byIcon(Icons.arrow_forward_rounded)))
          .color,
      kid.onAction,
    );
    expect(contrast(kid.onAction, kid.action), greaterThanOrEqualTo(4.5));
    expect(contrast(kid.action, kid.ground), greaterThanOrEqualTo(3));
  });

  testWidgets('the action icons grow with the text, in proportion to the '
      'digits, up to 200%', (tester) async {
    await pumpOn(tester, PinPad(onSubmit: (_) {}), ground: Ground.kid);
    final (icon1, digit1) = iconAndDigit(tester);
    expect(icon1, 28);
    expect(tester.widget<Icon>(find.byIcon(Icons.backspace_outlined)).size, 28);

    await pumpOn(
      tester,
      PinPad(onSubmit: (_) {}),
      ground: Ground.kid,
      textScale: 2,
    );
    final (icon2, digit2) = iconAndDigit(tester);
    expect(icon2, 56);
    expect(tester.widget<Icon>(find.byIcon(Icons.backspace_outlined)).size, 56);
    expect(icon2 / digit2, closeTo(icon1 / digit1, 1e-6));
    // Still inside its key.
    final key = tester.getRect(find.bySemanticsLabel('Confirmar'));
    final glyph = tester.getRect(find.byIcon(Icons.arrow_forward_rounded));
    expect(
      key.contains(glyph.topLeft) &&
          key.contains(glyph.bottomRight - const Offset(0.01, 0.01)),
      isTrue,
    );
  });

  testWidgets('a key takes its corner from the screen ratio', (tester) async {
    await pumpOn(tester, PinPad(onSubmit: (_) {}));
    final key = find.bySemanticsLabel('5');
    final shape =
        tester
                .widget<Material>(
                  find
                      .descendant(of: key, matching: find.byType(Material))
                      .first,
                )
                .shape!
            as RoundedRectangleBorder;
    final radius = (shape.borderRadius as BorderRadius).topLeft.x;
    expect(radius, closeTo(tester.getSize(key).height * 10 / 33, 0.01));
  });

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('holds at 200% text at $size', (tester) async {
      await pumpOn(
        tester,
        PinPad(onSubmit: (_) {}),
        size: size,
        textScale: 2,
        ground: Ground.kid,
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Confirmar').hitTestable(), findsOneWidget);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/tokens.dart';

import 'tevi_test.dart'
    show FigureLog, argb, colorsOf, paintTevi, rectNear, dark, cream;

/// A [FigureLog] that also keeps every move of the canvas: the opening
/// brings each part out by moving it, not by drawing it differently.
class MovingLog extends FigureLog {
  /// Each translate or scale, with how many draws came before it.
  final moves = <(int, Symbol, List<Object?>)>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #translate || name == #scale) {
      moves.add((draws.length, name, invocation.positionalArguments));
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

MovingLog paintAssembly(TeviAssembly assembly, {TeviLook? look}) {
  final log = MovingLog();
  TeviPainter(
    look: look ?? TeviLook.watching,
    assembly: assembly,
  ).paint(log, const Size.square(132));
  return log;
}

void main() {
  test('the body alone: one sun rounded rectangle, nothing else', () {
    final log = paintAssembly(TeviAssembly.body);
    expect(colorsOf(log), [argb(BrandColors.sun)]);
    expect(log.draws.single.bounds, rectNear(14, 20, 98, 90));
  });

  test('whole, it paints exactly the finished mascot', () {
    final whole = paintAssembly(TeviAssembly.whole);
    final plain = paintTevi();
    expect(colorsOf(whole), colorsOf(plain));
    expect(
      [for (final d in whole.draws) d.bounds],
      [for (final d in plain.draws) d.bounds],
    );
    expect(TeviAssembly.whole, const TeviAssembly());
  });

  test('the look wipes across from the tail\'s side, over a sun body', () {
    final log = paintAssembly(
      const TeviAssembly(look: .5, eye: 0, legs: 0, ends: 0),
    );
    expect(colorsOf(log), [
      argb(BrandColors.sun), // the whole body, under the wipe
      argb(BrandColors.sun), // the finished sun below the mask
      argb(dark), // crown
      argb(cream), // eyebrow
      argb(dark), // mask
    ]);
    final wipe = log.layers
        .where((l) => l.$2 == #clipRect && l.$1 == 1)
        .map((l) => l.$3! as Rect)
        .single;
    expect(wipe.left, lessThanOrEqualTo(14));
    expect(wipe.right, closeTo(14 + 84 * .5, 1e-9));
  });

  test('the eye opens from its centre', () {
    final log = paintAssembly(const TeviAssembly(eye: .5, legs: 0, ends: 0));
    expect(
      log.moves.where((m) => m.$2 == #scale && m.$3.first == .5),
      isNotEmpty,
    );
    final eye = log.draws.where((d) => argb(d.paint.color) == argb(cream));
    expect(eye, isNotEmpty);
  });

  test('the legs drop from under the body', () {
    final log = paintAssembly(const TeviAssembly(eye: 0, legs: .25, ends: 0));
    final drop = log.moves.where(
      (m) => m.$2 == #scale && m.$3.first == 1 && m.$3.last == .25,
    );
    expect(drop, hasLength(1));
    expect(
      log.draws.where((d) => d.name == #drawRRect && d.bounds.top == 87.6),
      hasLength(2),
    );
  });

  test('the beak and the tail slide out from behind the body', () {
    final log = paintAssembly(const TeviAssembly(ends: .5));
    final slides = [
      for (final m in log.moves)
        if (m.$2 == #translate && m.$3.last == 0) m.$3.first,
    ];
    expect(slides, containsAll([9.0, -9.0]));
  });

  test('with nothing out, the beak, tail, eye and legs are not drawn', () {
    final log = paintAssembly(
      const TeviAssembly(look: 1, eye: 0, legs: 0, ends: 0),
    );
    expect(colorsOf(log), [
      argb(BrandColors.sun),
      argb(dark),
      argb(cream),
      argb(dark),
    ]);
  });

  test('it repaints when the assembly moves', () {
    expect(
      const TeviPainter(assembly: TeviAssembly(look: .2))
          .shouldRepaint(const TeviPainter()),
      isTrue,
    );
    expect(const TeviPainter().shouldRepaint(const TeviPainter()), isFalse);
  });

  testWidgets('the widget hands its assembly to the painter', (tester) async {
    await tester.pumpWidget(
      const Center(child: Tevi(size: 66, assembly: TeviAssembly.body)),
    );
    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(Tevi),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as TeviPainter;
    expect(painter.assembly, TeviAssembly.body);
  });
}

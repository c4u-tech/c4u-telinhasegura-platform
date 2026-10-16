import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/family.dart';

/// Records every draw call: its name, its geometry and its paint's colour
/// (as ARGB: a colour read back from a Paint differs in float precision).
class RecordingCanvas implements Canvas {
  final colors = <int>{};
  final draws = <String>[];
  final paints = <Paint>[];
  double factor = 1;

  @override
  void scale(double sx, [double? sy]) => factor *= sx;

  /// Every clip, save and restore: how many draws came before it, its
  /// name, and a clip's bounds.
  final layers = <(int, String, Rect?)>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (name.contains('clip') ||
        name == 'Symbol("save")' ||
        name == 'Symbol("restore")') {
      final path = invocation.positionalArguments.firstOrNull;
      layers.add((draws.length, name, path is Path ? path.getBounds() : null));
      return null;
    }
    if (!name.contains('draw')) return null;
    final shape = <String>[];
    for (final arg in invocation.positionalArguments) {
      if (arg is Paint) {
        colors.add(arg.color.toARGB32());
        paints.add(arg);
      } else if (arg is Path) {
        shape.add(arg.getBounds().toString());
      } else {
        shape.add(arg.toString());
      }
    }
    draws.add('$name ${shape.join(' ')}');
    return null;
  }
}

RecordingCanvas record(Avatar avatar, {double size = 96, Color? boundary}) {
  final canvas = RecordingCanvas();
  AvatarPainter(avatar, boundary: boundary).paint(canvas, Size.square(size));
  return canvas;
}

void main() {
  test('no avatar paints sun, only ink, cream, dark and a tinted neutral', () {
    for (final avatar in Avatar.values) {
      for (final size in [40.0, 56.0, 96.0]) {
        final colors = record(avatar, size: size).colors;
        expect(colors, isNotEmpty, reason: avatar.name);
        expect(
          colors,
          isNot(contains(BrandColors.sun.toARGB32())),
          reason: avatar.name,
        );
        expect(
          AvatarColors.all.map((c) => c.toARGB32()).toSet().containsAll(colors),
          isTrue,
          reason: '${avatar.name} paints $colors',
        );
      }
    }
    expect(AvatarColors.all, isNot(contains(BrandColors.sun)));
    expect(AvatarColors.all, {
      BrandColors.ink,
      BrandColors.cream,
      BrandColors.dark,
      Palette.dark.muted,
    });
  });

  test('every animal has its own art, apart from the placeholder', () {
    final art = {for (final a in Avatar.values) a: record(a).draws.join('\n')};
    for (final avatar in Avatar.values) {
      // The disc, then the animal's own shapes.
      expect(
        record(avatar).draws.length,
        greaterThan(avatar == Avatar.unknown ? 1 : 3),
        reason: avatar.name,
      );
    }
    expect(art.values.toSet(), hasLength(Avatar.values.length));
  });

  test('on the kid ground the disc takes a 2 px boundary in the outline '
      'tone, on its edge, over the avatar\'s own unchanged colours', () {
    final outline = Palette.kid.outline;
    for (final avatar in Avatar.values) {
      for (final size in [96.0, 128.0, 192.0]) {
        final plain = record(avatar, size: size);
        final bounded = record(avatar, size: size, boundary: outline);
        // Everything the avatar paints, the same and in the same order.
        expect(
          bounded.draws.take(plain.draws.length),
          plain.draws,
          reason: avatar.name,
        );
        expect(bounded.draws, hasLength(plain.draws.length + 1));
        expect(bounded.colors, {
          ...plain.colors,
          outline.toARGB32(),
        }, reason: avatar.name);
        // Then the boundary: a stroke on the disc's edge, 2 px on screen.
        final ring = bounded.paints.last;
        expect(ring.color.toARGB32(), outline.toARGB32());
        expect(ring.style, PaintingStyle.stroke);
        expect(ring.strokeWidth * bounded.factor, closeTo(2, 1e-6));
        const circle = 'Symbol("drawCircle") Offset(32.0, 32.0) ';
        expect(bounded.draws.last, startsWith(circle));
        final radius = double.parse(
          bounded.draws.last.substring(circle.length),
        );
        // Its outer edge on the disc's: 1 px in from it, on screen.
        expect(radius * bounded.factor, closeTo(size / 2 - 1, 1e-6));
      }
    }
  });

  test('with the boundary, the animal is clipped to the disc inside the '
      'ring, and the ring itself is not', () {
    final outline = Palette.kid.outline;
    for (final avatar in Avatar.values) {
      for (final size in [96.0, 128.0, 192.0]) {
        final plain = record(avatar, size: size);
        final bounded = record(avatar, size: size, boundary: outline);
        // Right after the ground: the disc inside the ring and a ring's
        // width of ink, its edge 4 px in from the disc's on screen; never
        // without the boundary.
        bool inner((int, String, Rect?) l, double factor) =>
            l.$1 == 1 &&
            l.$2.contains('clip') &&
            l.$3 != null &&
            (l.$3!.center - const Offset(32, 32)).distance < 1e-4 &&
            (l.$3!.width / 2 * factor - (size / 2 - 4)).abs() < 1e-4;
        expect(
          bounded.layers.where((l) => inner(l, bounded.factor)),
          hasLength(1),
          reason: avatar.name,
        );
        expect(
          plain.layers.where((l) => inner(l, plain.factor)),
          isEmpty,
          reason: avatar.name,
        );
        // Lifted before the ring is drawn.
        expect(bounded.layers.last.$2, 'Symbol("restore")');
        expect(bounded.layers.last.$1, bounded.draws.length - 1);
      }
    }
  });

  testWidgets('a disc on the kid ground draws the boundary; elsewhere it '
      'does not', (tester) async {
    Color? boundaryUnder(ThemeData theme) {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(AvatarDisc),
          matching: find.byType(CustomPaint),
        ),
      );
      return (paint.painter! as AvatarPainter).boundary;
    }

    for (final (theme, boundary) in [
      (buildTheme(Brightness.dark, Palette.kid), Palette.kid.outline),
      (buildTheme(Brightness.light), null),
      (buildTheme(Brightness.dark), null),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: Center(child: AvatarDisc(Avatar.fox))),
        ),
      );
      await tester.pumpAndSettle();
      expect(boundaryUnder(theme), boundary);
    }
  });

  Future<void> pumpDisc(WidgetTester tester, Widget disc) => tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: Center(child: disc)),
    ),
  );

  testWidgets('a disc is labelled with its animal at the asked size', (
    tester,
  ) async {
    await pumpDisc(tester, const AvatarDisc(Avatar.owl, size: 56));
    expect(find.bySemanticsLabel('coruja'), findsOneWidget);
    expect(tester.getSize(find.byType(AvatarDisc)), const Size.square(56));

    await pumpDisc(tester, const AvatarDisc(Avatar.unknown));
    expect(find.bySemanticsLabel('avatar não informado'), findsOneWidget);
    expect(tester.getSize(find.byType(AvatarDisc)), const Size.square(40));
  });

  testWidgets('a decorative disc stays out of the semantics tree', (
    tester,
  ) async {
    await pumpDisc(
      tester,
      const AvatarDisc(Avatar.fox, excludeSemantics: true),
    );
    expect(find.bySemanticsLabel('raposa'), findsNothing);
  });
}

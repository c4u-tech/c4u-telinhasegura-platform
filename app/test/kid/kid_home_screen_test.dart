import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/kid/empty_shelf.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/kid/kid_layout.dart';
import 'package:telinha_segura/parental/app_mode.dart';

import '../access/harness.dart';
import '../family/avatars_test.dart' show RecordingCanvas;
import '../parental/fakes.dart';
import '../parental/parental_api_test.dart' show profileJson;

/// `/crianca` on a shared device locked to [minorId]; the profile read
/// answers [profile] (Lia by default).
Future<Harness> kidHome(
  WidgetTester tester, {
  String? minorId = 'm1',
  FutureOr<http.Response> Function()? profile,
  Size size = const Size(390, 844),
}) async {
  final h = Harness(
    signedIn: true,
    api: (req) => switch (req.url.path) {
      '/v1/child/profile' => (profile ?? () => json(200, profileJson))(),
      // No shelves yet: the empty shelf.
      '/v1/child/catalog' => json(200, {'themes': []}),
      _ => http.Response('', 204),
    },
  )..kidMode = {'minor_id': minorId};
  await h.pump(tester, initial: '/crianca', size: size);
  return h;
}

Finder get avatar => find.descendant(
  of: find.byType(KidHomeScreen),
  matching: find.byType(AvatarDisc),
);

String profileCalls(Harness h) =>
    h.calls.where((c) => c == 'GET /v1/child/profile').join(',');

/// Every semantics node a child could act on.
List<SemanticsNode> actionable(WidgetTester tester) => [
  for (final node in find.semantics.byPredicate((n) {
    final data = n.getSemanticsData();
    return data.hasAction(SemanticsAction.tap) ||
        data.hasAction(SemanticsAction.longPress) ||
        data.hasAction(SemanticsAction.setText);
  }).evaluate())
    node,
];

void main() {
  testWidgets('the child finds their avatar, large and centred, with the '
      'nickname beneath', (tester) async {
    final h = await kidHome(tester);

    expect(find.byType(KidLayout), findsOneWidget);
    expect(profileCalls(h), 'GET /v1/child/profile');
    final disc = tester.widget<AvatarDisc>(avatar);
    expect((disc.avatar, disc.size), (Avatar.fox, KidSizes.avatarLarge));
    final rect = tester.getRect(avatar);
    expect(rect.center.dx, closeTo(390 / 2, 0.5));
    final name = tester.getRect(find.text('Lia'));
    expect(name.top, greaterThan(rect.bottom));
    expect(name.center.dx, closeTo(rect.center.dx, 0.5));
  });

  testWidgets('at 840 px and wider the avatar, the nickname and the shelf '
      'scale up, still centred', (tester) async {
    final theme = Theme.of;
    await kidHome(tester, size: const Size(1280, 800));

    expect(tester.widget<AvatarDisc>(avatar).size, KidSizes.avatarWide);
    final rect = tester.getRect(avatar);
    expect(rect.size, const Size.square(KidSizes.avatarWide));
    expect(rect.center.dx, closeTo(1280 / 2, 0.5));
    final name = find.text('Lia');
    expect(
      tester.widget<Text>(name).style?.fontSize,
      theme(tester.element(name)).textTheme.displaySmall?.fontSize,
    );
    // The shelf grows as the avatar does: 128 to 192 dp is half again.
    final shelf = tester.getRect(
      find.descendant(
        of: find.byType(EmptyShelf),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(shelf.size, EmptyShelf.size * 1.5);
    expect(shelf.center.dx, closeTo(1280 / 2, 0.5));
    // Its line grows with it, two type steps: the 192 dp avatar and the
    // shelf read as one composition.
    final line = find.text(EmptyShelf.line);
    final text = theme(tester.element(line)).textTheme;
    final style = tester.widget<Text>(line).style;
    expect(style?.fontSize, text.titleLarge?.fontSize);
    expect(style?.height, text.titleLarge?.height);
    expect(style?.fontWeight, text.bodyLarge?.fontWeight);
  });

  testWidgets('narrower than 840 px they keep their sizes', (tester) async {
    final theme = Theme.of;
    await kidHome(tester, size: const Size(839, 800));
    expect(tester.widget<AvatarDisc>(avatar).size, KidSizes.avatarLarge);
    expect(
      tester.widget<Text>(find.text('Lia')).style?.fontSize,
      theme(tester.element(find.text('Lia'))).textTheme.headlineSmall?.fontSize,
    );
    expect(
      tester.getSize(
        find.descendant(
          of: find.byType(EmptyShelf),
          matching: find.byType(CustomPaint),
        ),
      ),
      EmptyShelf.size,
    );
    expect(
      tester.widget<Text>(find.text(EmptyShelf.line)).style?.fontSize,
      theme(tester.element(find.text(EmptyShelf.line)))
          .textTheme
          .bodyLarge
          ?.fontSize,
    );
  });

  for (final (size, disc) in [
    (const Size(390, 844), KidSizes.avatarLarge),
    (const Size(1440, 900), KidSizes.avatarWide),
  ]) {
    testWidgets('at ${size.width.toInt()} px the ${disc.toInt()} dp avatar '
        'keeps the animal clear inside its ring, ink between them: no ear '
        'reaches it (fix round, item 2)', (tester) async {
      await kidHome(tester, size: size);
      await tester.pumpAndSettle();

      expect(tester.getSize(avatar), Size.square(disc));
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: avatar,
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as AvatarPainter;
      expect(painter.boundary, isNotNull);
      final canvas = RecordingCanvas();
      painter.paint(canvas, Size.square(disc));
      // The animal's clip, centred on the disc: on screen, the 2 px ring
      // and a 2 px ink gap in from the disc's edge.
      final clips = [
        for (final l in canvas.layers)
          if (l.$2.contains('clip') && l.$3 != null) l.$3!.width / 2,
      ];
      expect(clips, hasLength(2));
      expect(clips.last * canvas.factor, closeTo(disc / 2 - 4, 1e-4));
    });
  }

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('at ${size.width.toInt()} px the exit\'s ring keeps 16 dp '
        'from the top and the side, level with the mark (fix round, item '
        '4)', (tester) async {
      await kidHome(tester, size: size);
      final control = find.byType(HoldToExit);
      final box = tester.getRect(control);
      // Held, the ring shows: its stroke's outer edge, 2 dp in from the
      // control's box.
      final hold = await tester.startGesture(tester.getCenter(control));
      await tester.pump(); // the press starts the clock
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.descendant(of: control, matching: find.byType(CustomPaint)).first,
        paints..circle(
          x: box.width / 2,
          y: box.height / 2,
          radius: box.width / 2 - 4,
        ),
      );
      await hold.up();
      final ring = box.deflate(2);
      expect(ring.top, greaterThanOrEqualTo(16));
      expect(size.width - ring.right, greaterThanOrEqualTo(16));
      final mark = find.descendant(
        of: find.byType(KidLayout),
        matching: find.bySemanticsLabel('Telinha Segura'),
      );
      expect(box.center.dy, tester.getCenter(mark).dy);
    });
  }

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('at ${size.width.toInt()} px the mark sits quietly at the '
        'strip\'s start: 24 px, 24 px in, on the exit\'s line', (tester) async {
      await kidHome(tester, size: size);
      final mark = tester.getRect(
        find.descendant(
          of: find.byType(KidLayout),
          matching: find.bySemanticsLabel('Telinha Segura'),
        ),
      );
      final exit = tester.getRect(find.byType(HoldToExit));

      expect(mark.size, const Size.square(24));
      expect(mark.left, Space.xl);
      expect(mark.center.dy, exit.center.dy);
    });
  }

  testWidgets('below, the empty shelf: the Espiadinha peeking into an empty '
      'screen and one short line', (tester) async {
    await kidHome(tester);

    final shelf = tester.getRect(find.byType(EmptyShelf));
    expect(shelf.top, greaterThan(tester.getRect(find.text('Lia')).bottom));
    expect(find.text(EmptyShelf.line), findsOneWidget);
    expect(EmptyShelf.line, 'Logo tem vídeo aqui');
    expect(
      tester.getRect(find.text(EmptyShelf.line)).top,
      greaterThan(shelf.top),
    );
  });

  testWidgets('only the exit control can be acted on', (tester) async {
    final semantics = tester.ensureSemantics();
    await kidHome(tester);

    final nodes = actionable(tester);
    expect(nodes.map((n) => n.label), [HoldToExit.label]);
    expect(find.byType(ButtonStyleButton), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    semantics.dispose();
  });

  testWidgets('a 2-second hold on the exit opens /crianca/sair', (
    tester,
  ) async {
    final h = await kidHome(tester);

    final hold = await tester.startGesture(
      tester.getCenter(find.byType(HoldToExit)),
    );
    await tester.pump(); // the press starts the clock
    await tester.pump(HoldToExit.hold + const Duration(milliseconds: 1));
    await hold.up();
    await tester.pumpAndSettle();

    expect(h.location(tester), '/crianca/sair');
  });

  group('without a profile, the neutral avatar and the exit', () {
    testWidgets('the child was deleted: no profile read', (tester) async {
      final h = await kidHome(tester, minorId: null);

      expect(h.services.appMode.mode, const SharedKid(null));
      expect(profileCalls(h), isEmpty);
      expect(tester.widget<AvatarDisc>(avatar).avatar, Avatar.unknown);
      expect(find.text('Lia'), findsNothing);
      expect(find.byType(HoldToExit), findsOneWidget);
    });

    testWidgets('the profile read fails', (tester) async {
      await kidHome(tester, profile: () => problem(410, 'profile_gone'));

      expect(tester.widget<AvatarDisc>(avatar).avatar, Avatar.unknown);
      expect(find.text('Lia'), findsNothing);
      expect(find.byType(HoldToExit), findsOneWidget);
    });
  });

  testWidgets('a linked device shows its child through its credential', (
    tester,
  ) async {
    final h = Harness(
      kind: ClientKind.mobile,
      devices: MemoryDeviceCredentialStore('dev'),
      api: (req) => req.url.path == '/v1/child/profile'
          ? json(200, {...profileJson, 'nickname': 'Téo', 'avatar': 'owl'})
          : http.Response('', 204),
    );
    await h.pump(tester, initial: '/crianca');

    expect(h.services.appMode.mode, const LinkedDevice('m1'));
    expect(tester.widget<AvatarDisc>(avatar).avatar, Avatar.owl);
    expect(find.text('Téo'), findsOneWidget);
  });

  testWidgets('a new child on the device shows at once', (tester) async {
    var nickname = 'Lia';
    final h = Harness(
      kind: ClientKind.mobile,
      devices: MemoryDeviceCredentialStore('dev'),
      api: (req) => req.url.path == '/v1/child/profile'
          ? json(200, {...profileJson, 'nickname': nickname})
          : http.Response('', 204),
    );
    await h.pump(tester, initial: '/crianca');
    expect(find.text('Lia'), findsOneWidget);

    nickname = 'Téo';
    h.services.appMode.restoreAs(const LinkedDevice('m2'));
    await tester.pumpAndSettle();

    expect(find.text('Téo'), findsOneWidget);
  });

  test('the shelf paints sun only in the head and fingers', () {
    final canvas = DrawLog();
    const EmptyShelfPainter().paint(canvas, EmptyShelf.size);

    String part(Rect bounds) => bounds.width > 20 ? 'head' : 'finger';
    final sun = [
      for (final (name, color, bounds) in canvas.draws)
        if (color == BrandColors.sun.toARGB32()) (name, part(bounds)),
    ];
    // The six fingertips and the head, cut flat: nothing else takes the
    // sun.
    expect(sun, [
      for (var i = 0; i < 6; i++) (#drawPath, 'finger'),
      (#drawPath, 'head'),
    ]);
    expect(
      {for (final (_, color, _) in canvas.draws) color},
      {
        BrandColors.sun.toARGB32(),
        BrandColors.cream.toARGB32(),
        BrandColors.dark.toARGB32(),
      },
      reason: 'a cream screen, the eyes in dark',
    );
  });
}

/// Records each draw: its name, its paint's colour (ARGB) and its
/// geometry's bounds in the painter's own units (transforms ignored).
class DrawLog implements Canvas {
  final draws = <(Symbol, int, Rect)>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (!name.toString().contains('draw')) return null;
    final args = invocation.positionalArguments;
    final paint = args.whereType<Paint>().single;
    final shape = args.first;
    final bounds = switch (shape) {
      Path() => shape.getBounds(),
      RRect() => shape.outerRect,
      Rect() => shape,
      _ => Rect.zero,
    };
    draws.add((name, paint.color.toARGB32(), bounds));
    return null;
  }
}

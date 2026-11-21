import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/design/tevi.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/kid/empty_shelf.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/kid/kid_error_note.dart';
import 'package:telinha_segura/kid/kid_layout.dart';
import 'package:telinha_segura/kid/mosaic.dart';
import 'package:telinha_segura/kid/paused_profile.dart';
import 'package:telinha_segura/kid/profile_picker_screen.dart';
import 'package:telinha_segura/parental/app_mode.dart';

import '../access/harness.dart';
import '../family/avatars_test.dart' show RecordingCanvas;
import '../parental/fakes.dart';
import '../parental/parental_api_test.dart' show profileJson;
import 'shelf_picture.dart';

/// `/crianca` on a shared device locked to [minorId]; the profile read
/// answers [profile] (Lia by default). The day has no videos yet, or,
/// [asleep], no time left.
Future<Harness> kidHome(
  WidgetTester tester, {
  String? minorId = 'm1',
  FutureOr<http.Response> Function()? profile,
  Size size = const Size(390, 844),
  bool asleep = false,
}) async {
  final h = Harness(
    signedIn: true,
    api: (req) => switch (req.url.path) {
      '/v1/child/profile' => (profile ?? () => json(200, profileJson))(),
      // No videos yet: the empty shelf.
      '/v1/child/catalog' => json(200, {
        'themes': <Object>[],
        if (asleep) 'time': {'state': 'time_up', 'reason': 'daily'},
      }),
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

/// What a screen reader hears for the avatar: the child's nickname.
Finder labelled(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

/// Whether the home stands on the night's dark.
bool nightGround(WidgetTester tester) =>
    tester
        .widget<Scaffold>(
          find
              .descendant(
                of: find.byType(KidLayout),
                matching: find.byType(Scaffold),
              )
              .first,
        )
        .backgroundColor ==
    BrandColors.dark;

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
  testWidgets('the child finds their avatar small at the strip\'s start, '
      'read by the nickname, level with the exit; no mark beside it', (
    tester,
  ) async {
    final h = await kidHome(tester);

    expect(find.byType(KidLayout), findsOneWidget);
    expect(profileCalls(h), 'GET /v1/child/profile');
    final disc = tester.widget<AvatarDisc>(avatar);
    expect((disc.avatar, disc.size), (Avatar.fox, KidMosaic.avatar));
    final rect = tester.getRect(avatar);
    expect(rect.left, KidLayout.edge(390));
    expect(rect.center.dy, tester.getCenter(find.byType(HoldToExit)).dy);
    expect(labelled('Lia'), findsOneWidget);
    expect(find.text('Lia'), findsNothing);
    // No mark drawn, though the strip still says the app's name.
    expect(
      find.byWidgetPredicate((w) => w is Tevi && w.tier == TeviTier.simplified),
      findsNothing,
    );
    expect(labelled(KidLayout.name), findsOneWidget);
  });

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('asleep at ${size.width.toInt()} px the strip is the home\'s: '
        'the avatar small at its start, read by the nickname, level with the '
        'exit; no mark, no large avatar, no nickname written', (tester) async {
      await kidHome(tester, size: size, asleep: true);

      final disc = tester.widget<AvatarDisc>(avatar);
      expect((disc.avatar, disc.size), (Avatar.fox, KidMosaic.avatar));
      final rect = tester.getRect(avatar);
      expect(rect.left, KidLayout.edge(size.width));
      expect(rect.center.dy, tester.getCenter(find.byType(HoldToExit)).dy);
      expect(labelled('Lia'), findsOneWidget);
      expect(find.text('Lia'), findsNothing);
      // No mark drawn, though the strip still says the app's name.
      expect(
        find.byWidgetPredicate(
          (w) => w is Tevi && w.tier == TeviTier.simplified,
        ),
        findsNothing,
      );
      expect(labelled(KidLayout.name), findsOneWidget);
    });
  }

  for (final (size, scale) in [
    (const Size(390, 844), 1.25),
    (const Size(839, 800), 1.25),
    (const Size(1280, 800), 1.5),
  ]) {
    testWidgets('at ${size.width.toInt()} px the empty shelf stands centred '
        'at ${scale}x, its line a title\'s size in the body\'s voice', (
      tester,
    ) async {
      final theme = Theme.of;
      await kidHome(tester, size: size);
      final shelf = tester.getRect(
        expectPerched(tester, find.byType(EmptyShelf), TeviLook.watching),
      );
      expect(shelf.size, ShelfPicture.size * scale);
      expect(shelf.center.dx, closeTo(size.width / 2, 0.5));
      final line = find.text(EmptyShelf.line);
      final text = theme(tester.element(line)).textTheme;
      final style = tester.widget<Text>(line).style;
      expect(style?.fontSize, text.titleLarge?.fontSize);
      expect(style?.height, text.titleLarge?.height);
      expect(style?.fontWeight, text.bodyLarge?.fontWeight);
    });
  }

  for (final disc in [KidSizes.avatar, ProfilePickerScreen.avatar]) {
    testWidgets('a ${disc.toInt()} dp avatar keeps the animal clear inside '
        'its ring, ink between them: no ear reaches it', (tester) async {
      // On the child's ink, where the ring is drawn.
      await tester.pumpWidget(
        Theme(
          data: buildTheme(Brightness.dark, Palette.kid),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: AvatarDisc(Avatar.fox, size: disc)),
          ),
        ),
      );

      final found = find.byType(AvatarDisc);
      expect(tester.getSize(found), Size.square(disc));
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: found,
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
        'from the top and the side, level with the avatar', (tester) async {
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
      expect(box.center.dy, tester.getCenter(avatar).dy);
    });
  }

  testWidgets('below the strip, the empty shelf: the mascot watching from '
      'the top of an empty screen, and one short line', (tester) async {
    await kidHome(tester);
    expectPerched(tester, find.byType(EmptyShelf), TeviLook.watching);

    final shelf = tester.getRect(find.byType(EmptyShelf));
    expect(shelf.top, greaterThan(tester.getRect(avatar).bottom));
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
    expect(labelled('Téo'), findsOneWidget);
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
    expect(labelled('Lia'), findsOneWidget);

    nickname = 'Téo';
    h.services.appMode.restoreAs(const LinkedDevice('m2'));
    await tester.pumpAndSettle();

    expect(labelled('Téo'), findsOneWidget);
  });

  group('a paused profile', () {
    /// `/crianca` for a child whose consent is not current: the child
    /// routes answer `consent_required`.
    Future<Harness> pausedHome(WidgetTester tester, {Size? size}) async {
      final h = Harness(
        signedIn: true,
        api: (req) => req.url.path.startsWith('/v1/child/')
            ? problem(403, 'consent_required')
            : http.Response('', 204),
      )..kidMode = {'minor_id': 'm1'};
      await h.pump(
        tester,
        initial: '/crianca',
        size: size ?? const Size(390, 844),
      );
      return h;
    }

    testWidgets('it says so in the shelf\'s place, calmly, for the adult '
        'nearby', (tester) async {
      await pausedHome(tester);

      expect(find.byType(PausedProfile), findsOneWidget);
      // On the night's dark, the mascot asleep on its wire, as on a day
      // without time: nothing to do until an adult comes.
      expectPerched(
        tester,
        find.byType(PausedProfile),
        TeviLook.asleep,
        perch: Perch.wire,
        night: true,
      );
      expect(nightGround(tester), isTrue);
      expect(
        PausedProfile.line,
        'Este perfil está pausado. Peça a um adulto para abrir o app e '
        'autorizar de novo.',
      );
      expect(find.text(PausedProfile.line), findsOneWidget);
      expect(find.byType(EmptyShelf), findsNothing);
      expect(find.byType(KidErrorNote), findsNothing);
      expect(find.text('Tentar de novo'), findsNothing);
      // The neutral avatar: the profile read is paused too.
      expect(tester.widget<AvatarDisc>(avatar).avatar, Avatar.unknown);
    });

    testWidgets('nothing leaves kid mode but the exit behind the PIN', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = await pausedHome(tester);

      expect(actionable(tester).map((n) => n.label), [HoldToExit.label]);
      expect(find.byType(ButtonStyleButton), findsNothing);
      expect(h.services.appMode.mode, isNot(const Guardian()));
      semantics.dispose();
    });

    testWidgets('it asks again on the wake beat, and wakes once the adult '
        'authorizes', (tester) async {
      var paused = true;
      final h = Harness(
        signedIn: true,
        api: (req) => switch (req.url.path) {
          _ when paused && req.url.path.startsWith('/v1/child/') => problem(
            403,
            'consent_required',
          ),
          '/v1/child/profile' => json(200, profileJson),
          '/v1/child/catalog' => json(200, {'themes': []}),
          _ => http.Response('', 204),
        },
      )..kidMode = {'minor_id': 'm1'};
      await h.pump(tester, initial: '/crianca');
      expect(find.byType(PausedProfile), findsOneWidget);

      paused = false;
      await tester.pump(KidHomeScreen.wake);
      await tester.pumpAndSettle();

      expect(find.byType(PausedProfile), findsNothing);
      expect(find.byType(EmptyShelf), findsOneWidget);
      expect(labelled('Lia'), findsOneWidget);
    });
  });
}

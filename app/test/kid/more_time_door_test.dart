import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart' show ErrorNote;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/design/pin_pad.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/profile_fields.dart' show SelectableRow;
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_exit_screen.dart';
import 'package:telinha_segura/kid/shelves.dart';
import 'package:telinha_segura/kid/sleeping_telinha.dart';
import 'package:telinha_segura/parental/app_mode.dart';

import '../access/harness.dart';
import '../kid_mode/hand_over_screen_test.dart' show pumpUntil;
import '../kid_mode/set_pin_screen_test.dart' show modules, padEnabled;
import '../parental/fakes.dart';
import '../parental/parental_api_test.dart' show profileJson;
import 'kid_exit_screen_test.dart' show submit;
import 'kid_shelves_test.dart' show pixel;
import 'link_out_test.dart' show leavingShared;
import 'sleeping_home_test.dart' show catalogReads, day, shelvesOn;

/// The door's choices, in order.
const choices = ['Mais 15 min', 'Mais 30 min', 'Mais 60 min', HoldToExit.label];

/// A child on a used-up day, on a shared device or a linked one; the
/// extension answers [extend] (the day then has time again), the unlock
/// lifts the lock.
Future<Harness> asleepAtTheDoor(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? extend,
  bool linked = false,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  var time = day('time_up', 'daily');
  late final Harness h;
  FutureOr<http.Response> api(http.Request req) {
    final path = req.url.path;
    if (path == '/v1/child/profile') return json(200, profileJson);
    if (path == '/v1/child/catalog') return json(200, shelvesOn(time));
    if (path.startsWith('/v1/child/thumbs/')) {
      return http.Response.bytes(pixel, 200);
    }
    if (path == '/v1/child/time/extend') {
      if (extend != null) return extend(req);
      time = day('ok');
      return json(200, {...day('ok'), 'remaining_seconds': 1800});
    }
    if (path == '/v1/child/unlock') {
      h.kidMode = null;
      return http.Response('', 204);
    }
    if (path == '/v1/child/profiles') {
      return json(200, {
        'profiles': [profileJson],
      });
    }
    return http.Response('', 204);
  }

  h = linked
      ? Harness(
          kind: ClientKind.mobile,
          devices: MemoryDeviceCredentialStore('dev'),
          api: api,
        )
      : (Harness(signedIn: true, api: api)..kidMode = {'minor_id': 'm1'});
  await h.pump(tester, initial: '/crianca', size: size, textScale: textScale);
  expect(find.byType(SleepingTelinha), findsOneWidget);
  await holdExit(tester);
  return h;
}

/// Holds the corner exit for its two seconds.
Future<void> holdExit(WidgetTester tester) async {
  final hold = await tester.startGesture(
    tester.getCenter(find.byType(HoldToExit)),
  );
  await tester.pump(); // the press starts the clock
  await tester.pump(HoldToExit.hold + const Duration(milliseconds: 1));
  await hold.up();
  await tester.pumpAndSettle();
}

/// The choice read as [label], a key or the exit's row.
Finder row(String label) =>
    find.byWidgetPredicate((w) => w is SelectableRow && w.label == label);

/// Which choice is checked.
String? chosen(WidgetTester tester) => [
  for (final c in choices)
    if (tester.widget<SelectableRow>(row(c)).selected) c,
].singleOrNull;

Future<void> choose(WidgetTester tester, String label) async {
  await tester.ensureVisible(row(label));
  await tester.tap(row(label));
  await tester.pump();
}

/// The words [label]'s choice shows sit on one line.
void expectOneLine(WidgetTester tester, String label) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: row(label), matching: find.byType(RichText)),
  );
  final length = paragraph.text.toPlainText().length;
  final lines = {
    for (final box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: length),
    ))
      box.top,
  };
  expect(lines, hasLength(1), reason: '$label wraps');
}

/// Whether the three times stand in one row of keys.
bool keyed(WidgetTester tester) =>
    {for (final c in choices.take(3)) tester.getRect(row(c)).top}.length == 1;

List<String> extensions(Harness h) =>
    h.actions.where((c) => c.contains('/time/extend')).toList();

void main() {
  // The real face, not the test font's square glyphs: whether a key's
  // words fit is a question of their true widths.
  setUpAll(() async {
    await (FontLoader(
      Typefaces.family,
    )..addFont(rootBundle.load('assets/fonts/BricolageGrotesque.ttf'))).load();
  });

  testWidgets('opened from the sleeping home, the door offers 15, 30 or 60 '
      'more minutes and its usual exit above the pad, the exit chosen', (
    tester,
  ) async {
    await asleepAtTheDoor(tester);

    expect(find.byType(KidExitScreen), findsOneWidget);
    expect(find.byType(SelectableRow), findsNWidgets(4));
    // One row of three keys, then the usual exit as the one full-width
    // row.
    final keys = [for (final c in choices.take(3)) tester.getRect(row(c))];
    expect({for (final k in keys) k.top}, hasLength(1));
    expect(keys[0].right, lessThan(keys[1].left));
    expect(keys[1].right, lessThan(keys[2].left));
    for (final (key, words) in [
      // The number and its unit held together.
      (keys[0], '15 min'),
      (keys[1], '30 min'),
      (keys[2], '60 min'),
    ]) {
      expect(key.contains(tester.getCenter(find.text(words))), isTrue);
    }
    final exit = tester.getRect(row(HoldToExit.label));
    expect(exit.top, greaterThan(keys[0].bottom));
    expect(exit.width, closeTo(keys[2].right - keys[0].left, 0.5));
    expect(
      tester.getRect(row(HoldToExit.label)).bottom,
      lessThan(tester.getRect(find.byType(PinPad)).top),
    );
    expect(chosen(tester), HoldToExit.label);
  });

  testWidgets('the choices are 64 dp kid-palette rows read as radios', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await asleepAtTheDoor(tester);

    for (final c in choices) {
      expect(tester.getSize(row(c)).height, greaterThanOrEqualTo(64));
      expect(
        tester.getSemantics(find.bySemanticsLabel(c)),
        isSemantics(
          label: c,
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          isChecked: c == HoldToExit.label,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
    }
    await choose(tester, 'Mais 30 min');
    expect(chosen(tester), 'Mais 30 min');
    semantics.dispose();
  });

  for (final linked in [false, true]) {
    final device = linked ? 'linked' : 'shared';
    testWidgets('on a $device device, a time and the PIN extend the day once '
        'and return to the shelves, still in kid mode', (tester) async {
      final h = await asleepAtTheDoor(tester, linked: linked);
      final mode = h.services.appMode.mode;

      await choose(tester, 'Mais 30 min');
      await submit(tester, '2580');
      await tester.pumpAndSettle();

      expect(extensions(h), [
        'POST /v1/child/time/extend {"pin":"2580","minutes":30}',
      ]);
      expect(h.actions, isNot(contains(startsWith('POST /v1/child/unlock'))));
      expect(h.actions, isNot(contains(startsWith('POST /v1/child/profiles'))));
      expect(h.location(tester), '/crianca');
      expect(h.services.appMode.mode, mode);
      expect(catalogReads(h), 2);
      expect(find.byType(SleepingTelinha), findsNothing);
      expect(find.byType(Shelf), findsNWidgets(2));
    });
  }

  testWidgets('with the usual exit chosen, the PIN unlocks as it always did', (
    tester,
  ) async {
    final h = await asleepAtTheDoor(tester);

    await submit(tester, '2580');
    await pumpUntil(tester, () => h.services.appMode.mode is Guardian);
    await tester.pumpAndSettle();

    expect(h.actions, contains('POST /v1/child/unlock {"pin":"2580"}'));
    expect(extensions(h), isEmpty);
    expect(h.location(tester), '/');
  });

  testWidgets('on a linked device the usual exit opens the profile picker', (
    tester,
  ) async {
    final h = await asleepAtTheDoor(tester, linked: true);

    await submit(tester, '2580');
    await tester.pumpAndSettle();

    expect(h.actions, contains('POST /v1/child/profiles {"pin":"2580"}'));
    expect(extensions(h), isEmpty);
    expect(h.location(tester), '/crianca/quem');
  });

  testWidgets('over_cap says the day is at its 4 hours, empties the pad and '
      'keeps the choice', (tester) async {
    final h = await asleepAtTheDoor(
      tester,
      extend: (_) => problem(422, 'over_cap'),
    );

    await choose(tester, 'Mais 60 min');
    await submit(tester, '2580');
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(ErrorNote, 'Hoje já chega a 4 horas, o máximo.'),
      findsOneWidget,
    );
    expect(modules(tester), List.filled(6, false));
    expect(padEnabled(tester), isTrue);
    expect(chosen(tester), 'Mais 60 min');
    expect(h.location(tester), '/crianca/sair');
  });

  testWidgets('a wrong PIN on an extension says so as the exit does', (
    tester,
  ) async {
    await asleepAtTheDoor(tester, extend: (_) => problem(403, 'invalid_pin'));

    await choose(tester, 'Mais 15 min');
    await submit(tester, '1111');
    await tester.pumpAndSettle();

    expect(find.text('PIN errado. Tente de novo.'), findsOneWidget);
    expect(modules(tester), List.filled(6, false));
    expect(chosen(tester), 'Mais 15 min');
  });

  testWidgets('rate_limited on an extension disables the pad while the time '
      'left counts down', (tester) async {
    await asleepAtTheDoor(
      tester,
      extend: (_) =>
          problem(429, 'rate_limited', headers: {'retry-after': '30'}),
    );

    await choose(tester, 'Mais 15 min');
    await submit(tester, '1111');
    await pumpUntil(
      tester,
      () => find.textContaining('Muitas tentativas').evaluate().isNotEmpty,
    );

    expect(padEnabled(tester), isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(padEnabled(tester), isTrue);
  });

  group('anywhere else the door offers no time', () {
    testWidgets('from the shelves', (tester) async {
      final h = Harness(
        signedIn: true,
        api: (req) => switch (req.url.path) {
          '/v1/child/profile' => json(200, profileJson),
          '/v1/child/catalog' => json(200, shelvesOn(day('ok'))),
          _ => http.Response.bytes(pixel, 200),
        },
      )..kidMode = {'minor_id': 'm1'};
      await h.pump(tester, initial: '/crianca');
      await holdExit(tester);

      expect(find.byType(KidExitScreen), findsOneWidget);
      expect(find.byType(SelectableRow), findsNothing);
    });

    testWidgets('from a player\'s link', (tester) async {
      await leavingShared(tester);

      expect(find.byType(KidExitScreen), findsOneWidget);
      expect(find.byType(SelectableRow), findsNothing);
    });

    testWidgets('opened directly', (tester) async {
      final h = Harness(signedIn: true)..kidMode = {'minor_id': 'm1'};
      await h.pump(tester, initial: '/crianca/sair');

      expect(find.byType(KidExitScreen), findsOneWidget);
      expect(find.byType(SelectableRow), findsNothing);
    });

    testWidgets('the errand goes as the door takes it', (tester) async {
      final h = await asleepAtTheDoor(tester);
      expect(h.services.moreTimeErrand, isFalse);

      await tester.ensureVisible(find.text('Voltar'));
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(find.byType(SleepingTelinha), findsOneWidget);
      expect(h.services.moreTimeErrand, isFalse);
    });
  });

  testWidgets('at 360 × 640 the choices and the pad scroll, nothing '
      'overflows', (tester) async {
    await asleepAtTheDoor(tester, size: const Size(360, 640));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(row(HoldToExit.label)).width, 360 - 2 * Space.xl);
    await tester.ensureVisible(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('at ${size.width.toInt()} × ${size.height.toInt()}, with '
        'over_cap showing, the title, the choice, the note, the pad and '
        '"Voltar" are all in view', (tester) async {
      await asleepAtTheDoor(
        tester,
        extend: (_) => problem(422, 'over_cap'),
        size: size,
      );
      await choose(tester, 'Mais 60 min');
      await submit(tester, '2580');
      await tester.pumpAndSettle();
      expect(find.byType(ErrorNote), findsOneWidget);

      final view = Offset.zero & size;
      for (final part in [
        find.text('PIN dos pais'),
        row('Mais 15 min'),
        row(HoldToExit.label),
        find.byType(ErrorNote),
        find.bySemanticsLabel('Confirmar'),
        find.text('Voltar'),
      ]) {
        final rect = tester.getRect(part);
        expect(
          view.contains(rect.topLeft) && view.contains(rect.bottomRight),
          isTrue,
          reason: '$part at $rect',
        );
      }
      // Nothing had to scroll to get there.
      final scroll = find.descendant(
        of: find.byType(KidExitScreen),
        matching: find.byType(Scrollable),
      );
      expect(tester.state<ScrollableState>(scroll.first).position.pixels, 0);
    });
  }

  testWidgets('at 360 × 640 no time\'s words wrap, keys or rows (finish '
      'review)', (tester) async {
    await asleepAtTheDoor(tester, size: const Size(360, 640));

    expect(tester.takeException(), isNull);
    for (final c in choices) {
      expectOneLine(tester, c);
    }
  });

  testWidgets('at 2× text the times fall back to full-width rows, one '
      'line each, nothing overflowing, the choice as before (finish '
      'review)', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await asleepAtTheDoor(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(keyed(tester), isFalse);
    final exit = tester.getRect(row(HoldToExit.label));
    for (final c in choices) {
      expect(tester.getRect(row(c)).width, exit.width);
      // The usual exit's longer words may wrap at 2×; a time's do not.
      if (c != HoldToExit.label) expectOneLine(tester, c);
      expect(
        tester.getSemantics(find.bySemanticsLabel(c)),
        isSemantics(
          label: c,
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          isChecked: c == HoldToExit.label,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
    }
    await choose(tester, 'Mais 30 min');
    await submit(tester, '2580');
    await tester.pumpAndSettle();
    expect(extensions(h), [
      'POST /v1/child/time/extend {"pin":"2580","minutes":30}',
    ]);
    semantics.dispose();
  });

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('at ${size.width.toInt()} × ${size.height.toInt()} and 1× '
        'the times stand as one row of keys', (tester) async {
      await asleepAtTheDoor(tester, size: size);
      expect(keyed(tester), isTrue);
    });
  }
}

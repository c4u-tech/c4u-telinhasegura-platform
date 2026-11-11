import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/catalog/words.dart';
import 'package:telinha_segura/design/pin_pad.dart';
import 'package:telinha_segura/family/profile_fields.dart' show SelectableRow;
import 'package:telinha_segura/family/widgets.dart' show FamilyPlaceholder;
import 'package:telinha_segura/kid/player_screen.dart';

import '../access/harness.dart';
import '../kid/kid_shelves_test.dart' show pixel, twoShelves;
import '../kid_mode/set_pin_screen_test.dart' show modules, padEnabled;
import '../parental/parental_api_test.dart' show profileJson;
import '../screentime/fixtures.dart' show rulesJson;
import 'fixtures.dart';

/// Lia's day: [left] minutes she may still watch now.
http.Response today(
  int left, {
  int daily = 90,
  int extension = 0,
  int used = 40,
  String state = 'ok',
}) => json(
  200,
  rulesJson(
    dailyMinutes: daily,
    extension: extension,
    usedSeconds: used * 60,
    state: state,
    remainingSeconds: left * 60,
  ),
);

const path = '/familia/videos/m1/f1/assistir';

/// The start of Lia's 1 h 30 min film, opened by its address. [rules]
/// answers each read of her day, [session] each start; the hand-over
/// locks the session and the child's play resumes at 754 s.
Future<Harness> starting(
  WidgetTester tester, {
  FutureOr<http.Response> Function()? rules,
  FutureOr<http.Response> Function(http.Request)? session,
  FutureOr<http.Response> Function(http.Request)? handOver,
  String initial = path,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  late final Harness h;
  final catalog = catalogApi(catalog: (_, _) => page(liaWithFamily));
  h =
      Harness(
          signedIn: true,
          api: (req) {
            final p = req.url.path;
            if (p == '/v1/screentime/minors/m1') {
              return (rules ?? () => today(100))();
            }
            if (p == '/v1/family/minors/m1/sessions') {
              return (session ??
                  (_) => json(201, {'session_id': 's1', 'start_seconds': 754}))(
                req,
              );
            }
            if (p == '/v1/parental/kid-mode') {
              if (handOver != null) return handOver(req);
              h.kidMode = {'minor_id': 'm1'};
              return http.Response('', 204);
            }
            if (p == '/v1/child/profile') return json(200, profileJson);
            if (p == '/v1/child/catalog') return json(200, twoShelves);
            if (p.startsWith('/v1/child/thumbs/')) {
              return http.Response.bytes(pixel, 200);
            }
            if (p == '/v1/child/plays') {
              return json(201, {
                'play_id': 'p1',
                'youtube_id': 'yt-f1',
                'remaining_seconds': 6000,
                'start_seconds': 754,
              });
            }
            if (p.endsWith('/beat')) {
              return json(200, {'state': 'ok', 'remaining_seconds': 600});
            }
            return catalog(req);
          },
        )
        ..family = threeChildren
        ..pinSet = true;
  await h.pump(tester, initial: initial, size: size, textScale: textScale);
  return h;
}

const choices = ['Sem mais tempo', 'Mais 15 min', 'Mais 30 min', 'Mais 60 min'];

Finder choice(String label) =>
    find.byWidgetPredicate((w) => w is SelectableRow && w.label == label);

String? chosen(WidgetTester tester) => [
  for (final c in choices)
    if (tester.widget<SelectableRow>(choice(c)).selected) c,
].singleOrNull;

bool waits(WidgetTester tester, String label) =>
    tester.widget<SelectableRow>(choice(label)).onTap == null;

List<String> starts(Harness h) =>
    h.actions.where((c) => c.contains('/sessions')).toList();

List<String> dayReads(Harness h) =>
    h.actions.where((c) => c == 'GET /v1/screentime/minors/m1').toList();

/// Types [pin], each key brought into view, and presses the pad's start
/// key; [settle] waits for what follows.
Future<void> begin(
  WidgetTester tester, [
  String pin = '1234',
  bool settle = true,
]) async {
  for (final d in [...pin.split(''), CatalogWords.begin]) {
    final key = find.bySemanticsLabel(d);
    await tester.ensureVisible(key);
    await tester.pumpAndSettle();
    await tester.tap(key);
    await tester.pump();
  }
  if (settle) await tester.pumpAndSettle();
}

/// The [Text] whose words, non-breaking spaces made plain, are [words].
Finder plain(String words) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll(' ', ' ') == words,
);

void main() {
  testWidgets('titled "Assistir com Lia": the work and its length, Lia\'s '
      'day, the time choice, then the PIN pad and its "Começar"', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await starting(tester);

    final order = [
      find.text('Assistir com Lia'),
      find.text('A grande viagem do sapo'),
      plain('1 h 30 min'),
      plain('Hoje Lia ainda tem 1 h 40 min.'),
      choice('Sem mais tempo'),
      choice('Mais 15 min'),
      find.text(CatalogWords.pinHeading),
      find.byType(PinPad),
    ];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    final tops = [for (final f in order) tester.getTopLeft(f).dy];
    expect(tops, [...tops]..sort());
    expect(find.bySemanticsLabel(CatalogWords.begin), findsOneWidget);
    expect(find.bySemanticsLabel('Confirmar'), findsNothing);
    expect(
      tester.getSemantics(find.text(CatalogWords.pinHeading)),
      isSemantics(label: CatalogWords.pinHeading, isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets('when it fits, "Sem mais tempo" is chosen and nothing says '
      'it is short', (tester) async {
    await starting(tester);

    expect(chosen(tester), 'Sem mais tempo');
    expect(find.textContaining('Para caber hoje'), findsNothing);
    for (final c in choices) {
      expect(waits(tester, c), isFalse, reason: c);
    }
  });

  testWidgets('when it does not fit, it says how much is missing and the '
      'smallest time that makes it fit is chosen; the smaller ones wait', (
    tester,
  ) async {
    await starting(tester, rules: () => today(72));

    expect(
      plain('Hoje Lia ainda tem 1 h 12 min. Para caber hoje, faltam 18 min.'),
      findsOneWidget,
    );
    expect(chosen(tester), 'Mais 30 min');
    expect(waits(tester, 'Sem mais tempo'), isTrue);
    expect(waits(tester, 'Mais 15 min'), isTrue);
    expect(waits(tester, 'Mais 60 min'), isFalse);
  });

  testWidgets('when no time can make it fit, it says so, with neither the '
      'keys nor the PIN pad', (tester) async {
    await starting(tester, rules: () => today(40, daily: 200, used: 160));

    expect(
      plain('Hoje Lia ainda tem 40 min. Esse filme não cabe mais hoje.'),
      findsOneWidget,
    );
    expect(find.byType(SelectableRow), findsNothing);
    expect(find.byType(PinPad), findsNothing);
  });

  testWidgets('outside her hours the day line says it is not the time', (
    tester,
  ) async {
    await starting(
      tester,
      rules: () => today(0, used: 10, state: 'outside_window'),
    );

    // Outside the hours more time opens them only for its own minutes,
    // and 60 cannot hold a film of 1 h 30 min.
    expect(
      plain('Agora não é hora para Lia. Esse filme não cabe mais hoje.'),
      findsOneWidget,
    );
    expect(find.byType(PinPad), findsNothing);
  });

  testWidgets('"Começar" starts with the PIN and the time chosen, hands the '
      'device to Lia and opens the film in her player, already resuming', (
    tester,
  ) async {
    final h = await starting(tester, rules: () => today(72));

    await begin(tester);

    expect(starts(h), [
      'POST /v1/family/minors/m1/sessions '
          '{"video_id":"f1","pin":"1234","extend_minutes":30}',
    ]);
    expect(h.actions, contains('POST /v1/parental/kid-mode {"minor_id":"m1"}'));
    expect(h.location(tester), '/crianca/assistir/f1');
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(h.actions, contains('POST /v1/child/plays {"video_id":"f1"}'));
    expect(h.player.current?.youtubeId, 'yt-f1');
    expect(h.player.current?.start, 754);
  });

  testWidgets('with no more time chosen, the start sends none', (tester) async {
    final h = await starting(tester);

    await begin(tester);

    expect(starts(h), [
      'POST /v1/family/minors/m1/sessions {"video_id":"f1","pin":"1234"}',
    ]);
  });

  testWidgets('a hand-over that fails leaves the guardian here with the '
      'error note', (tester) async {
    final h = await starting(tester, handOver: (_) => problem(500, 'internal'));

    await begin(tester);

    expect(h.location(tester), path);
    expect(find.byType(ErrorNote), findsOneWidget);
    expect(find.byType(PinPad), findsOneWidget);
  });

  group('a refused start keeps the choice and says why', () {
    testWidgets('a wrong PIN empties the pad and shows the error note', (
      tester,
    ) async {
      await starting(
        tester,
        rules: () => today(72),
        session: (_) => problem(403, 'invalid_pin'),
      );

      await begin(tester);

      expect(
        find.widgetWithText(ErrorNote, 'PIN errado. Tente de novo.'),
        findsOneWidget,
      );
      expect(modules(tester), List.filled(6, false));
      expect(chosen(tester), 'Mais 30 min');
      expect(
        tester.getTopLeft(find.byType(ErrorNote)).dy,
        lessThan(tester.getTopLeft(find.byType(PinPad)).dy),
      );
    });

    testWidgets('too many tries: the wait, the pad held', (tester) async {
      await starting(
        tester,
        session: (_) =>
            problem(429, 'rate_limited', headers: {'retry-after': '120'}),
      );

      await begin(tester, '1234', false);
      await tester.pump();

      expect(find.textContaining('2 min'), findsOneWidget);
      expect(padEnabled(tester), isFalse);
      expect(chosen(tester), 'Sem mais tempo');
      await tester.pump(const Duration(minutes: 3));
    });

    testWidgets('over the cap: "Hoje já chega a 4 horas, o máximo."', (
      tester,
    ) async {
      await starting(
        tester,
        rules: () => today(72),
        session: (_) => problem(422, 'over_cap'),
      );

      await begin(tester);

      expect(
        find.widgetWithText(ErrorNote, 'Hoje já chega a 4 horas, o máximo.'),
        findsOneWidget,
      );
      expect(chosen(tester), 'Mais 30 min');
    });

    testWidgets('it no longer fits: the day is read again and the time '
        'chosen again', (tester) async {
      var left = 100;
      final h = await starting(
        tester,
        rules: () => today(left),
        session: (_) {
          left = 72;
          return problem(
            403,
            'does_not_fit',
            extra: {'remaining_seconds': 72 * 60},
          );
        },
      );
      expect(chosen(tester), 'Sem mais tempo');

      await begin(tester);

      expect(dayReads(h), hasLength(2));
      expect(chosen(tester), 'Mais 30 min');
      expect(
        plain('Hoje Lia ainda tem 1 h 12 min. Para caber hoje, faltam 18 min.'),
        findsOneWidget,
      );
      expect(modules(tester), List.filled(6, false));
    });

    testWidgets('not the time: "Agora não é hora para Lia."', (tester) async {
      await starting(tester, session: (_) => problem(403, 'time_up'));

      await begin(tester);

      expect(
        find.widgetWithText(ErrorNote, 'Agora não é hora para Lia.'),
        findsOneWidget,
      );
    });

    testWidgets('a video gone from the catalogue goes back with the notice', (
      tester,
    ) async {
      final h = await starting(
        tester,
        session: (_) => problem(403, 'video_not_allowed'),
      );

      await begin(tester);

      expect(h.location(tester), '/familia/criancas/m1');
      expect(find.widgetWithText(Notice, videoGone), findsOneWidget);
    });

    testWidgets('a profile to authorize again opens the re-consent, which '
        'returns here', (tester) async {
      final h = await starting(
        tester,
        session: (_) => problem(403, 'consent_required'),
      );

      await begin(tester);

      expect(
        h.location(tester),
        '/familia/criancas/m1/autorizar?depois=${Uri.encodeComponent(path)}',
      );
    });

    testWidgets('a network failure keeps the PIN and the choice, with the '
        'error note and "Tentar de novo"', (tester) async {
      var tries = 0;
      final h = await starting(
        tester,
        rules: () => today(72),
        session: (_) {
          if (tries++ == 0) throw http.ClientException('offline');
          return json(201, {'session_id': 's1', 'start_seconds': 0});
        },
      );

      await begin(tester);

      expect(find.byType(ErrorNote), findsOneWidget);
      expect(modules(tester).where((m) => m), hasLength(4));
      expect(chosen(tester), 'Mais 30 min');

      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Tentar de novo'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Tentar de novo'));
      await tester.pumpAndSettle();

      expect(starts(h), hasLength(2));
      expect(starts(h).toSet(), hasLength(1), reason: 'the same start again');
      expect(h.location(tester), '/crianca/assistir/f1');
    });
  });

  testWidgets('the loading placeholder while the day is read', (tester) async {
    final day = Completer<http.Response>();
    await starting(tester, rules: () => day.future);

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    expect(find.byType(PinPad), findsNothing);

    day.complete(today(100));
    await tester.pumpAndSettle();
    expect(find.byType(PinPad), findsOneWidget);
  });

  testWidgets('a day that cannot be read offers "Tentar de novo"', (
    tester,
  ) async {
    var fail = true;
    final h = await starting(
      tester,
      rules: () => fail ? problem(500, 'internal') : today(100),
    );

    expect(find.byType(ErrorNote), findsOneWidget);
    expect(find.byType(PinPad), findsNothing);

    fail = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Tentar de novo'));
    await tester.pumpAndSettle();

    expect(dayReads(h), hasLength(2));
    expect(find.byType(PinPad), findsOneWidget);
  });

  testWidgets('opened for a video watched alone, it leads to the video\'s '
      'screen', (tester) async {
    final h = await starting(tester, initial: '/familia/videos/m1/v1/assistir');

    expect(h.location(tester), '/familia/videos/m1/v1');
    expect(starts(h), isEmpty);
  });

  testWidgets('back returns to the video\'s screen', (tester) async {
    final h = await starting(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/videos/m1/f1');
  });

  testWidgets('holds at 200 % text at 360 × 640', (tester) async {
    await starting(
      tester,
      rules: () => today(72),
      size: const Size(360, 640),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(chosen(tester), 'Mais 30 min');
  });
}

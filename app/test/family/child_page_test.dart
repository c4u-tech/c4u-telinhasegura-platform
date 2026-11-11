import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/catalog/family_video_screen.dart';
import 'package:telinha_segura/catalog/pack_rows.dart';
import 'package:telinha_segura/catalog/video_row.dart';
import 'package:telinha_segura/catalog/words.dart';
import 'package:telinha_segura/design/display_title.dart';
import 'package:telinha_segura/family/child_page.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/family.dart' show AgeBand;
import 'package:telinha_segura/family/reconsent_screen.dart' show needsConsent;
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/screentime/today.dart';
import 'package:telinha_segura/shell/guardian_shell.dart';

import '../access/harness.dart';
import '../catalog/fixtures.dart';
import '../screentime/fixtures.dart';
import 'fixtures.dart';

const phone = Size(412, 915);
const wide = Size(1280, 800);

/// Five videos Lia can see, so the page shows the first and "Ver todos".
final liaFive = [
  familyItem('v1', 'O sapo que pulava alto'),
  familyItem('v2', 'Gatinhos no quintal', channel: 'Canal X', seconds: 240),
  familyItem('v3', 'A canção das cores', theme: 'musica', seconds: 150),
  familyItem('v4', 'Vaca amarela', seconds: 300),
  familyItem('v5', 'Canção de ninar', theme: 'musica', seconds: 420),
];

/// The child page's reads and writes: screen time for the day, the
/// catalogue for the videos, and the profile's deletion, which empties
/// the family.
FutureOr<http.Response> Function(http.Request) pageApi(
  Harness Function() harness, {
  FutureOr<http.Response> Function()? rules,
  FutureOr<http.Response> Function()? usage,
  FutureOr<http.Response> Function(String minorId, int offset)? catalog,
  FutureOr<http.Response> Function(http.Request)? write,
}) {
  final time = screenTimeApi(rules: {'m1': ?rules}, usage: usage);
  final videos = catalogApi(
    catalog: catalog ?? (_, _) => page(liaFive, packs: liaPacks),
    write: write,
  );
  return (req) {
    final path = req.url.path;
    if (path.startsWith('/v1/screentime/')) return time(req);
    if (path == '/v1/family/minors/m1' && req.method == 'DELETE') {
      harness().family = familyWith([]);
      return http.Response('', 204);
    }
    return videos(req);
  };
}

Future<Harness> childPage(
  WidgetTester tester, {
  Map<String, Object?>? family,
  FutureOr<http.Response> Function()? rules,
  FutureOr<http.Response> Function()? usage,
  FutureOr<http.Response> Function(String minorId, int offset)? catalog,
  FutureOr<http.Response> Function(http.Request)? write,
  String id = 'm1',
  String? initial,
  Size size = phone,
  double textScale = 1,
}) async {
  late final Harness h;
  h = Harness(
    signedIn: true,
    api: pageApi(
      () => h,
      rules: rules,
      usage: usage,
      catalog: catalog,
      write: write,
    ),
  )..family = family ?? familyWith([minorJson('m1', 'Lia')]);
  await h.pump(
    tester,
    initial: initial ?? '/familia/criancas/$id',
    size: size,
    textScale: textScale,
  );
  return h;
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder door(String title) => find.widgetWithText(DoorRow, title);

Finder header(String title) =>
    find.byWidgetPredicate((w) => w is SectionTitle && w.title == title);

Finder hideOf(String title) => find.byWidgetPredicate(
  (w) =>
      w is QuietAction &&
      w.label == 'Esconder' &&
      w.semanticsLabel == 'Esconder “$title” para Lia',
);

double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

void main() {
  group('with room for two columns', () {
    Rect rectOf(WidgetTester tester, Key key) =>
        tester.getRect(find.byKey(key));

    testWidgets('a desktop window sets Hoje and Vídeos side by side, Perfil '
        'below at their full width', (tester) async {
      await childPage(tester, size: const Size(1440, 900));

      final today = rectOf(tester, ChildPage.todayKey);
      final videos = rectOf(tester, ChildPage.videosKey);
      final profile = rectOf(tester, ChildPage.profileKey);
      expect(videos.top, today.top);
      expect(videos.left, greaterThan(today.right));
      expect(profile.top, greaterThan(today.bottom));
      expect(profile.left, today.left);
      expect(profile.right, videos.right);
      expect(tester.takeException(), isNull);
    });

    testWidgets('side by side on dark too', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await childPage(tester, size: const Size(1440, 900));

      expect(
        rectOf(tester, ChildPage.videosKey).top,
        rectOf(tester, ChildPage.todayKey).top,
      );
    });

    testWidgets('at 200 % text the larger list leaves one column, nothing '
        'clipped', (tester) async {
      await childPage(tester, size: const Size(1440, 900), textScale: 2);

      expect(tester.takeException(), isNull);
      expect(
        rectOf(tester, ChildPage.videosKey).top,
        greaterThan(rectOf(tester, ChildPage.todayKey).bottom),
      );
    });

    testWidgets('a 10 to 11 inch tablet in landscape sets Hoje and Vídeos '
        'side by side beside the list, nothing clipped', (tester) async {
      await childPage(tester, size: const Size(1317, 823));

      final today = rectOf(tester, ChildPage.todayKey);
      final videos = rectOf(tester, ChildPage.videosKey);
      expect(videos.top, today.top);
      expect(videos.left, greaterThan(today.right));
      expect(tester.takeException(), isNull);
    });

    for (final size in [phone, const Size(900, 800)]) {
      testWidgets('at ${size.width} keeps one column', (tester) async {
        await childPage(tester, size: size);

        final today = rectOf(tester, ChildPage.todayKey);
        final videos = rectOf(tester, ChildPage.videosKey);
        expect(videos.top, greaterThan(today.bottom));
        expect(videos.left, today.left);
      });
    }
  });

  group('one page', () {
    testWidgets('a header with the avatar, the nickname and the age band, '
        'then Hoje, Vídeos and Perfil in order', (tester) async {
      await childPage(tester);

      expect(find.widgetWithText(DisplayTitle, 'Lia'), findsOneWidget);
      // The band under the nickname, above the first section.
      expect(
        top(tester, find.text('5 a 8 anos').first),
        lessThan(top(tester, header('Hoje'))),
      );
      expect(
        tester.getTopLeft(find.byType(AvatarDisc).first).dx,
        lessThan(tester.getTopLeft(find.byType(DisplayTitle)).dx),
      );
      final order = [
        find.widgetWithText(DisplayTitle, 'Lia'),
        header('Hoje'),
        header('Vídeos'),
        header('Perfil'),
      ];
      for (final f in order) {
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        expect(f, findsOneWidget);
      }
      for (var i = 1; i < order.length; i++) {
        expect(top(tester, order[i - 1]), lessThan(top(tester, order[i])));
      }
    });

    testWidgets('the section titles are headers', (tester) async {
      final semantics = tester.ensureSemantics();
      await childPage(tester);

      for (final title in ['Hoje', 'Vídeos', 'Perfil']) {
        await tester.ensureVisible(header(title));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.text(title).first),
          isSemantics(label: title, isHeader: true),
        );
      }
      semantics.dispose();
    });

    testWidgets('a task screen: no bottom bar on a phone', (tester) async {
      await childPage(tester);

      expect(find.byType(ShellBar), findsNothing);
      expect(find.byTooltip('Voltar'), findsOneWidget);
    });

    testWidgets('beside the rail on a wide window, with its back', (
      tester,
    ) async {
      await childPage(tester, size: wide);

      expect(find.byType(InkRail), findsOneWidget);
      expect(find.byTooltip('Voltar'), findsOneWidget);
      expect(find.widgetWithText(DisplayTitle, 'Lia'), findsOneWidget);
    });

    testWidgets('back returns to the children', (tester) async {
      final h = await childPage(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/criancas');
    });

    testWidgets('system back goes where the arrow goes: the children', (
      tester,
    ) async {
      final h = await childPage(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/criancas');
    });

    testWidgets('opened from Início, system back returns to Início', (
      tester,
    ) async {
      final h = await childPage(tester, initial: '/');
      await tapOn(tester, find.text('Lia').first);
      expect(h.location(tester), '/familia/criancas/m1');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
    });

    testWidgets('on iOS, opened from the children, the page pops plainly '
        'to them', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await childPage(tester);

      final route = ModalRoute.of(tester.element(find.byType(ChildPage)))!;
      expect(route.popDisposition, RoutePopDisposition.pop);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('opened from Início, back goes there at once, never through '
        'the children', (tester) async {
      final h = await childPage(tester, initial: '/');
      await tapOn(tester, find.text('Lia').first);
      final seen = <String>[];
      final router = GoRouter.of(tester.element(find.byType(ChildPage)));
      void note() => seen.add(router.state.uri.path);
      router.routerDelegate.addListener(note);
      addTearDown(() => router.routerDelegate.removeListener(note));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
      expect(seen, isNot(contains('/familia/criancas')));
    });

    testWidgets('leaving for a task from a page opened from Início stays on '
        'the task', (tester) async {
      final h = await childPage(tester, initial: '/');
      await tapOn(tester, find.text('Lia').first);

      await tapOn(
        tester,
        find.widgetWithText(PrimaryButton, 'Mais tempo hoje'),
      );

      expect(h.location(tester), '/familia/tempo/m1/mais');
    });

    testWidgets('a paused child leads to its new authorization', (
      tester,
    ) async {
      final h = await childPage(
        tester,
        family: familyWith([pausedMinorJson('m1', 'Lia')]),
      );

      await tapOn(tester, door(needsConsent));

      expect(h.location(tester), '/familia/criancas/m1/autorizar');
    });

    for (final (name, ground, scale) in [
      ('dark', Brightness.dark, 1.0),
      ('200 % text', Brightness.light, 2.0),
    ]) {
      testWidgets('holds in $name, every section reachable', (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = ground;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await childPage(tester, textScale: scale);

        expect(tester.takeException(), isNull);
        for (final f in [
          find.text('Mais tempo hoje'),
          door('Limite e horário'),
          find.text('Ver todos os vídeos'),
          find.text('Editar'),
          find.text('Excluir perfil'),
        ]) {
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          expect(f, findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Hoje', () {
    testWidgets('the modules and the words, as on Início', (tester) async {
      await childPage(
        tester,
        rules: () =>
            json(200, rulesJson(dailyMinutes: 50, usedSeconds: 30 * 60)),
      );

      expect(find.text('30 de 50 min'), findsOneWidget);
      final filled = tester
          .widgetList<StateModule>(
            find.descendant(
              of: find.byType(TodayTime),
              matching: find.byType(StateModule),
            ),
          )
          .map((m) => m.filled)
          .toList();
      expect(filled, [true, true, true, false, false]);
    });

    for (final (state, json_, words) in [
      (
        'spent',
        rulesJson(dailyMinutes: 50, usedSeconds: 50 * 60),
        TodayWords.spent,
      ),
      (
        'outside the hours',
        rulesJson(usedSeconds: 10 * 60, state: 'outside_window'),
        '10 de 90 min · fora do horário',
      ),
    ]) {
      testWidgets('$state reads "$words"', (tester) async {
        await childPage(tester, rules: () => json(200, json_));

        expect(find.text(words), findsOneWidget);
      });
    }

    testWidgets('a failed read says "tempo indisponível", and Tentar de novo '
        'reads again', (tester) async {
      var fail = true;
      await childPage(
        tester,
        rules: () =>
            fail ? problem(503, 'unavailable') : json(200, rulesJson()),
      );

      expect(find.text(TodayWords.unavailable), findsOneWidget);
      fail = false;
      await tapOn(
        tester,
        find.descendant(
          of: find.byKey(ChildPage.todayKey),
          matching: find.text('Tentar de novo'),
        ),
      );

      expect(find.text(TodayWords.unavailable), findsNothing);
      expect(find.text('40 de 90 min'), findsOneWidget);
    });

    testWidgets('loading shows the quiet bar, read as loading', (tester) async {
      final answer = Completer<http.Response>();
      await childPage(tester, rules: () => answer.future);

      expect(find.byKey(TodayTime.placeholderKey), findsOneWidget);
      answer.complete(json(200, rulesJson()));
      await tester.pumpAndSettle();
      expect(find.byKey(TodayTime.placeholderKey), findsNothing);
    });

    testWidgets('"Mais tempo hoje" is the filled primary, opening more time', (
      tester,
    ) async {
      final h = await childPage(tester);

      await tapOn(
        tester,
        find.widgetWithText(PrimaryButton, 'Mais tempo hoje'),
      );

      expect(h.location(tester), '/familia/tempo/m1/mais');
    });

    testWidgets('"Limite e horário" is a row with the rules, opening them', (
      tester,
    ) async {
      final h = await childPage(
        tester,
        rules: () => json(200, rulesJson(isDefault: true)),
      );

      for (final line in [
        '90 min por dia · das 08:00 às 19:30',
        'Padrão da faixa 5 a 8 anos',
      ]) {
        expect(
          find.descendant(
            of: door('Limite e horário'),
            matching: find.text(line),
          ),
          findsOneWidget,
        );
      }
      await tapOn(tester, door('Limite e horário'));

      expect(h.location(tester), '/familia/tempo/m1/limite');
    });

    testWidgets('the six days before today as figure rows under "Dias '
        'anteriores", none a target; today is not repeated', (tester) async {
      final semantics = tester.ensureSemantics();
      await childPage(tester);

      expect(find.text('Últimos 7 dias'), findsNothing);
      expect(find.textContaining('Hoje ·'), findsNothing);
      final heading = find.text('Dias anteriores');
      expect(
        tester.widget<Text>(heading).style?.fontSize,
        Theme.of(tester.element(heading)).textTheme.titleMedium?.fontSize,
      );
      final rows = tester
          .widgetList<FigureRow>(find.byType(FigureRow))
          .map((r) => (r.label, r.figure))
          .toList();
      expect(rows, [
        ('Ontem', '1 h 10 min'),
        ('Sáb', '0 min'),
        ('Sex', '0 min'),
        ('Qui', '0 min'),
        ('Qua', '0 min'),
        ('Ter', '0 min'),
      ]);
      for (final r in find.byType(FigureRow).evaluate()) {
        expect(
          (r.renderObject! as RenderBox).size.height,
          greaterThanOrEqualTo(48),
        );
      }
      expect(
        find.ancestor(
          of: find.byType(FigureRow).first,
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
      expect(
        top(tester, heading),
        lessThan(top(tester, find.byType(FigureRow).first)),
      );
      semantics.dispose();
    });

    testWidgets('coming back from more time reads the day again', (
      tester,
    ) async {
      var used = 40;
      final h = await childPage(
        tester,
        rules: () => json(200, rulesJson(usedSeconds: used * 60)),
      );

      await tapOn(
        tester,
        find.widgetWithText(PrimaryButton, 'Mais tempo hoje'),
      );
      used = 55;
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/criancas/m1');
      expect(find.text('55 de 90 min'), findsOneWidget);
    });
  });

  group('Vídeos', () {
    testWidgets('at 200 % text the rows drop their pictures', (tester) async {
      await childPage(tester, textScale: 2);
      expect(find.byType(VideoRow), findsWidgets);
      expect(find.byType(PackRow), findsWidgets);
      expect(find.byType(VideoThumb), findsNothing);
    });

    testWidgets('at 100 % text the rows keep their pictures', (tester) async {
      await childPage(tester);
      expect(find.byType(VideoThumb), findsNWidgets(2 + ChildPage.firstVideos));
    });

    testWidgets('"Esconder" keeps a 48 dp target, its word close under the '
        'row\'s line', (tester) async {
      await childPage(tester);

      final button = find.ancestor(
        of: find.text('Esconder').first,
        matching: find.byType(TextButton),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      final meta = find.text('Ciência Pequena\u00a0· 6\u00a0min');
      final gap =
          tester.getTopLeft(find.text('Esconder').first).dy -
          tester.getBottomLeft(meta.first).dy;
      expect(gap, inInclusiveRange(4, 12));
    });

    testWidgets('today\'s pacotinhos, then the first videos, each with a '
        'quiet Esconder', (tester) async {
      await childPage(tester);

      for (final pack in ['Bichos da fazenda', 'Hora de dormir']) {
        expect(door(pack), findsOneWidget);
      }
      for (final title in ['O sapo que pulava alto', 'Gatinhos no quintal']) {
        expect(door(title), findsOneWidget);
        expect(hideOf(title), findsOneWidget);
      }
      expect(
        find.byWidgetPredicate(
          (w) => w is QuietAction && w.label == 'Esconder',
        ),
        findsNWidgets(ChildPage.firstVideos),
      );
      expect(door('Canção de ninar'), findsNothing);
      expect(
        top(tester, door('Hora de dormir')),
        lessThan(top(tester, door('O sapo que pulava alto'))),
      );
    });

    testWidgets('a video hidden already stays off the page', (tester) async {
      await childPage(
        tester,
        catalog: (_, _) => page([
          familyItem('v1', 'O sapo que pulava alto', hidden: true),
          familyItem('v2', 'Gatinhos no quintal'),
        ]),
      );

      expect(door('O sapo que pulava alto'), findsNothing);
      expect(door('Gatinhos no quintal'), findsOneWidget);
      expect(door('Ver todos os vídeos'), findsOneWidget);
    });

    testWidgets('Esconder hides it for Lia in place, with a calm notice and '
        'Desfazer', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await childPage(tester);
      h.calls.clear();

      await tapOn(tester, hideOf('O sapo que pulava alto'));

      expect(h.actions, ['PUT /v1/family/minors/m1/hidden/v1']);
      expect(door('O sapo que pulava alto'), findsNothing);
      expect(find.text(CatalogWords.hidden('Lia')), findsOneWidget);
      expect(find.byType(ErrorNote), findsNothing);
      final undo = find.widgetWithText(QuietAction, 'Desfazer');
      expect(undo, findsOneWidget);
      expect(tester.widget<QuietAction>(undo).destructive, isFalse);
      expect(
        find.bySemanticsLabel(
          'Mostrar “O sapo que pulava alto” para Lia de '
          'novo',
        ),
        findsOne,
      );
      expect(h.location(tester), '/familia/criancas/m1');
      expect(
        tester.getSemantics(find.text(CatalogWords.hidden('Lia'))),
        isSemantics(isLiveRegion: true),
      );
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused, isNotNull);
      expect(
        find.ancestor(
          of: find.byWidget(focused!.widget),
          matching: find.widgetWithText(QuietAction, 'Desfazer'),
        ),
        findsOneWidget,
      );
      // "Desfazer" starts on the column's edge, like the notice above it;
      // its focus ring stands outside the word, 3 px into the margin.
      final column = tester.getRect(find.byKey(ChildPage.videosKey));
      expect(
        tester.getTopLeft(find.text('Desfazer')).dx,
        tester.getTopLeft(find.text(CatalogWords.hidden('Lia'))).dx,
      );
      expect(tester.getTopLeft(find.text('Desfazer')).dx, column.left);
      semantics.dispose();
    });

    testWidgets('Desfazer shows it again, back in its place', (tester) async {
      final h = await childPage(tester);
      await tapOn(tester, hideOf('O sapo que pulava alto'));
      h.calls.clear();

      await tapOn(tester, find.text('Desfazer'));

      expect(h.actions.where((a) => !a.contains('/thumbs/')), [
        'DELETE /v1/family/minors/m1/hidden/v1',
      ]);
      expect(find.text(CatalogWords.hidden('Lia')), findsNothing);
      expect(door('O sapo que pulava alto'), findsOneWidget);
      expect(hideOf('O sapo que pulava alto'), findsOneWidget);
    });

    testWidgets('a failed hide keeps the row and says so calmly under it', (
      tester,
    ) async {
      await childPage(tester, write: (_) => throw http.ClientException('down'));

      await tapOn(tester, hideOf('O sapo que pulava alto'));

      expect(door('O sapo que pulava alto'), findsOneWidget);
      expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
      expect(find.text('Desfazer'), findsNothing);
      expect(
        top(tester, find.byType(ErrorNote)),
        greaterThan(top(tester, door('O sapo que pulava alto'))),
      );
    });

    testWidgets('"Ver todos os vídeos" opens the full list when there are '
        'more', (tester) async {
      final h = await childPage(tester);

      await tapOn(tester, door('Ver todos os vídeos'));

      expect(h.location(tester), '/familia/videos/m1');
    });

    testWidgets('no "Ver todos" when the page shows them all', (tester) async {
      await childPage(tester, catalog: (_, _) => page(liaFive.sublist(0, 2)));

      expect(door('Ver todos os vídeos'), findsNothing);
    });

    testWidgets('with nothing released yet it says so calmly', (tester) async {
      await childPage(tester, catalog: (_, _) => page([]));

      expect(find.text(CatalogWords.empty(AgeBand.from5To8)), findsOneWidget);
      expect(find.byType(ErrorNote), findsNothing);
    });

    testWidgets('a failed read offers Tentar de novo', (tester) async {
      var fail = true;
      await childPage(
        tester,
        catalog: (_, _) => fail ? problem(503, 'unavailable') : page(liaFive),
      );

      final videos = find.byKey(ChildPage.videosKey);
      expect(
        find.descendant(of: videos, matching: find.byType(ErrorNote)),
        findsOneWidget,
      );
      fail = false;
      await tapOn(
        tester,
        find.descendant(of: videos, matching: find.text('Tentar de novo')),
      );

      expect(find.byType(ErrorNote), findsNothing);
      expect(door('O sapo que pulava alto'), findsOneWidget);
    });

    testWidgets('a video opens its screen, with Denunciar', (tester) async {
      final h = await childPage(tester);

      await tapOn(tester, door('O sapo que pulava alto'));

      expect(h.location(tester), '/familia/videos/m1/v1');
      expect(find.byType(FamilyVideoScreen), findsOneWidget);
      expect(find.text('Denunciar este vídeo'), findsOneWidget);
    });

    testWidgets('a pacotinho opens its screen', (tester) async {
      final h = await childPage(tester);

      await tapOn(tester, door('Hora de dormir'));

      expect(h.location(tester), '/familia/videos/m1/pacotinho/k2');
    });
  });

  group('Perfil', () {
    testWidgets('the nickname, avatar and age band with Editar, opening the '
        'form', (tester) async {
      final h = await childPage(tester);

      final profile = find.byKey(ChildPage.profileKey);
      for (final words in ['Lia', '5 a 8 anos', 'Editar']) {
        expect(
          find.descendant(of: profile, matching: find.text(words)),
          findsOneWidget,
        );
      }
      await tapOn(tester, find.text('Editar'));

      expect(h.location(tester), '/familia/criancas/m1/editar');
      expect(find.widgetWithText(DisplayTitle, 'Editar perfil'), findsOne);
    });

    testWidgets('Excluir perfil is quiet clay at the foot, asking first', (
      tester,
    ) async {
      final h = await childPage(tester);
      final delete = find.widgetWithText(QuietAction, 'Excluir perfil');
      expect(tester.widget<QuietAction>(delete).destructive, isTrue);
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      expect(top(tester, delete), greaterThan(top(tester, header('Perfil'))));

      await tapOn(tester, find.text('Excluir perfil'));

      final confirmation = tester.widget<DestructiveConfirmation>(
        find.byType(DestructiveConfirmation),
      );
      expect(confirmation.title, 'Excluir perfil');
      expect(
        confirmation.body.first,
        startsWith('O perfil de Lia será apagado'),
      );
      expect(h.actions.where((a) => a.startsWith('DELETE')), isEmpty);
    });

    testWidgets('confirming deletes the child and returns to the refreshed '
        'list', (tester) async {
      final h = await childPage(tester);

      await tapOn(tester, find.text('Excluir perfil'));
      await tapOn(
        tester,
        find.descendant(
          of: find.byType(DestructiveConfirmation),
          matching: find.widgetWithText(PrimaryButton, 'Excluir perfil'),
        ),
      );

      expect(h.actions.where((a) => a.startsWith('DELETE')), [
        'DELETE /v1/family/minors/m1',
      ]);
      expect(h.location(tester), '/familia/criancas');
      expect(find.text('0 de 10 crianças'), findsOneWidget);
    });
  });

  group('Excluir perfil, asked first', () {
    testWidgets('it starts on the column\'s edge, and so does Cancelar', (
      tester,
    ) async {
      await childPage(tester);
      double edgeOf(Finder finder) => tester.getTopLeft(finder).dx;
      final edge = edgeOf(find.byType(FilledButton).first);
      await tester.ensureVisible(find.text('Excluir perfil'));
      await tester.pumpAndSettle();
      expect(edgeOf(find.text('Excluir perfil')), edge);

      await tapOn(tester, find.text('Excluir perfil'));

      expect(edgeOf(find.text('Cancelar')), edge);
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      final h = await childPage(tester);

      await tapOn(tester, find.text('Excluir perfil'));
      await tapOn(tester, find.text('Cancelar'));

      expect(find.byType(DestructiveConfirmation), findsNothing);
      expect(h.actions.where((a) => a.startsWith('DELETE')), isEmpty);
      expect(h.location(tester), '/familia/criancas/m1');
    });

    testWidgets('a stale sign-in asks to confirm it is you, then deletes', (
      tester,
    ) async {
      var confirmed = false;
      late final Harness h;
      final page = pageApi(() => h);
      h = Harness(
        signedIn: true,
        api: (req) {
          if (req.url.path == '/v1/session/reauth') {
            confirmed = true;
            return http.Response('', 204);
          }
          if (req.method == 'DELETE' && !confirmed) {
            return problem(403, 'reauth_required');
          }
          return page(req);
        },
      )..family = familyWith([minorJson('m1', 'Lia')]);
      await h.pump(tester, initial: '/familia/criancas/m1', size: phone);

      await tapOn(tester, find.text('Excluir perfil'));
      await tapOn(
        tester,
        find.descendant(
          of: find.byType(DestructiveConfirmation),
          matching: find.widgetWithText(PrimaryButton, 'Excluir perfil'),
        ),
      );
      expect(find.byType(ReauthPrompt), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'uma senha longa');
      await tester.pumpAndSettle();
      await tapOn(tester, find.text('Confirmar'));

      expect(
        h.actions.where((a) => a.startsWith('DELETE') || a.contains('reauth')),
        [
          'DELETE /v1/family/minors/m1',
          'POST /v1/session/reauth {"password":"uma senha longa"}',
          'DELETE /v1/family/minors/m1',
        ],
      );
      expect(h.location(tester), '/familia/criancas');
    });
  });

  group('a child that no longer exists', () {
    testWidgets('an id the family does not hold returns to the children '
        'with a notice', (tester) async {
      final h = await childPage(tester, id: 'gone');

      expect(h.location(tester), '/familia/criancas');
      expect(find.text(Copy.childGone), findsOneWidget);
    });

    testWidgets('not_found from a read does the same', (tester) async {
      final h = await childPage(tester, rules: () => problem(404, 'not_found'));

      expect(h.location(tester), '/familia/criancas');
      expect(find.text(Copy.childGone), findsOneWidget);
    });

    testWidgets('removed while open, it does the same', (tester) async {
      final h = await childPage(tester);

      h.family = familyWith([]);
      await h.services.familyModel.refresh();
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/criancas');
      expect(find.text(Copy.childGone), findsOneWidget);
    });
  });
}

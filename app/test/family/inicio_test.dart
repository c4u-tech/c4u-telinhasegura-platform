import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/band_transition.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/inicio.dart';
import 'package:telinha_segura/family/reconsent_screen.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/parental/app_mode.dart';
import 'package:telinha_segura/shell/guardian_shell.dart';

import '../access/harness.dart';
import '../parental/parental_api_test.dart' show profileJson;
import '../screentime/fixtures.dart';
import 'fixtures.dart';

final threeChildren = [
  minorJson('m1', 'Lia'),
  minorJson('m2', 'Téo', avatar: 'owl'),
  minorJson('m3', 'Nina', avatar: 'cat'),
];

/// Início for a family holding [minors], each child's rules answered by
/// [rules] (90 min a day, 40 used, by default); the hand-over answers
/// [handOver] (204 by default, the session then locked).
Future<Harness> inicio(
  WidgetTester tester, {
  List<Map<String, Object?>>? minors,
  Map<String, FutureOr<http.Response> Function()> rules = const {},
  FutureOr<http.Response> Function(http.Request)? handOver,
  Size size = const Size(390, 844),
  double textScale = 1,
  List<String> roles = const [],
  DateTime? now,
}) async {
  late final Harness h;
  final time = screenTimeApi(rules: rules);
  h =
      Harness(
          signedIn: true,
          api: (req) {
            if (req.url.path == '/v1/parental/kid-mode') {
              if (handOver != null) return handOver(req);
              h.kidMode = {'minor_id': 'm1'};
              return http.Response('', 204);
            }
            if (req.url.path == '/v1/child/profile') {
              return json(200, profileJson);
            }
            return time(req);
          },
        )
        ..family = familyWith(minors ?? threeChildren)
        ..pinSet = true
        ..roles = roles;
  await withClock(Clock.fixed(now ?? DateTime(2026, 11, 10, 15)), () async {
    await h.pump(tester, initial: '/', size: size, textScale: textScale);
  });
  return h;
}

Finder row(String nickname) => find.byWidgetPredicate(
  (w) => w is ChildRow && w.minor.nickname == nickname,
);

Finder inRow(String nickname, Finder f) =>
    find.descendant(of: row(nickname), matching: f);

List<bool> modules(WidgetTester tester, String nickname) => tester
    .widgetList<StateModule>(inRow(nickname, find.byType(StateModule)))
    .map((m) => m.filled)
    .toList();

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  group('the greeting', () {
    for (final (hour, words) in [
      (5, 'Bom dia'),
      (9, 'Bom dia'),
      (11, 'Bom dia'),
      (12, 'Boa tarde'),
      (17, 'Boa tarde'),
      (18, 'Boa noite'),
      (23, 'Boa noite'),
      (0, 'Boa noite'),
      (4, 'Boa noite'),
    ]) {
      test('at $hour h it is $words', () {
        expect(greeting(DateTime(2026, 11, 10, hour, 30)), words);
      });
    }

    testWidgets('Início greets by the local time, as its title', (
      tester,
    ) async {
      await inicio(tester, now: DateTime(2026, 11, 10, 9));

      expect(find.text('Bom dia'), findsOneWidget);
      expect(find.text('Sua família'), findsNothing);
    });
  });

  group('the children', () {
    testWidgets(
      'one row per child: avatar, nickname, today and the hand-over',
      (tester) async {
        await inicio(tester);

        expect(find.byType(ChildRow), findsNWidgets(3));
        for (final name in ['Lia', 'Téo', 'Nina']) {
          expect(inRow(name, find.text(name)), findsOneWidget);
          final avatar = tester.widget<AvatarDisc>(
            inRow(name, find.byType(AvatarDisc)),
          );
          expect(avatar.size, 56);
          expect(
            inRow(
              name,
              find.widgetWithText(PrimaryButton, 'Entregar para $name'),
            ),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets('ten children are ten rows, the screen scrolling to the '
        'last', (tester) async {
      await inicio(
        tester,
        minors: [for (var i = 0; i < 10; i++) minorJson('m$i', 'Criança $i')],
      );

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Entregar para Criança 9'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Entregar para Criança 9'), findsOneWidget);
    });

    testWidgets('the rows stand on a low-alpha ink band, divided by reed '
        'hairlines, with no card and no shadow', (tester) async {
      await inicio(tester);

      final band = tester.widget<DecoratedBox>(find.byKey(ChildBand.bandKey));
      final box = band.decoration as BoxDecoration;
      expect(box.color, ChildBand.tint(Palette.light));
      expect(box.color!.a, lessThan(.2));
      expect(box.boxShadow, isNull);
      expect(find.byType(Card), findsNothing);
      final hairlines = tester.widgetList<Divider>(
        find.descendant(
          of: find.byKey(ChildBand.bandKey),
          matching: find.byType(Divider),
        ),
      );
      expect(hairlines, hasLength(2));
      for (final h in hairlines) {
        expect(h.color, Palette.light.outline.withValues(alpha: .5));
      }
    });

    testWidgets('on a wide window the rows stand in two columns beside the '
        'rail', (tester) async {
      await inicio(tester, size: const Size(1280, 800));

      expect(find.byType(InkRail), findsOneWidget);
      expect(
        tester.getTopLeft(row('Lia')).dy,
        tester.getTopLeft(row('Téo')).dy,
      );
      expect(
        tester.getTopLeft(row('Téo')).dx,
        greaterThan(tester.getTopRight(row('Lia')).dx - 1),
      );
      expect(
        tester.getTopLeft(row('Nina')).dy,
        greaterThan(tester.getBottomLeft(row('Lia')).dy - 1),
      );
    });

    testWidgets('on a phone the rows stack in one column', (tester) async {
      await inicio(tester);

      expect(
        tester.getTopLeft(row('Téo')).dy,
        greaterThan(tester.getBottomLeft(row('Lia')).dy - 1),
      );
    });

    for (final (ground, brightness) in [
      ('light', Brightness.light),
      ('dark', Brightness.dark),
    ]) {
      testWidgets('holds at 200 % text on a 360 dp phone, $ground', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await inicio(
          tester,
          size: const Size(360, 780),
          textScale: 2,
          rules: {'m2': () => json(200, rulesJson(state: 'time_up'))},
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Entregar para Lia'), findsOneWidget);
        final band = tester.widget<DecoratedBox>(find.byKey(ChildBand.bandKey));
        expect(
          (band.decoration as BoxDecoration).color,
          ChildBand.tint(
            brightness == Brightness.light ? Palette.light : Palette.dark,
          ),
        );
      });
    }
  });

  group('today\'s time', () {
    testWidgets('reads "{usado} de {limite} min" beside five screen modules', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await inicio(
        tester,
        rules: {
          'm1': () =>
              json(200, rulesJson(dailyMinutes: 50, usedSeconds: 30 * 60)),
        },
      );

      expect(inRow('Lia', find.text('30 de 50\u00a0min')), findsOneWidget);
      expect(modules(tester, 'Lia'), [true, true, true, false, false]);
      expect(find.bySemanticsLabel('Hoje, 30 de 50\u00a0min'), findsOne);
      semantics.dispose();
    });

    testWidgets('today\'s extension counts in the limit', (tester) async {
      await inicio(
        tester,
        rules: {
          'm1': () => json(
            200,
            rulesJson(dailyMinutes: 50, usedSeconds: 30 * 60, extension: 10),
          ),
        },
      );

      expect(inRow('Lia', find.text('30 de 60\u00a0min')), findsOneWidget);
    });

    testWidgets('each row reads its own child', (tester) async {
      final h = await inicio(tester);

      for (final id in ['m1', 'm2', 'm3']) {
        expect(h.calls, contains('GET /v1/screentime/minors/$id'));
      }
    });

    testWidgets('while it loads, a quiet placeholder stands in its place', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final answer = Completer<http.Response>();
      await inicio(tester, rules: {'m1': () => answer.future});

      expect(
        inRow('Lia', find.byKey(ChildRow.todayPlaceholderKey)),
        findsOneWidget,
      );
      expect(inRow('Lia', find.byType(StateModule)), findsNothing);
      expect(find.bySemanticsLabel('Carregando o tempo de hoje'), findsOne);
      // The other rows do not wait for it.
      expect(inRow('Téo', find.text('40 de 90\u00a0min')), findsOneWidget);

      answer.complete(json(200, rulesJson()));
      await tester.pumpAndSettle();
      expect(inRow('Lia', find.text('40 de 90\u00a0min')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a failed read says "tempo indisponível" and Entregar still '
        'works', (tester) async {
      final h = await inicio(
        tester,
        rules: {'m1': () => problem(503, 'unavailable')},
      );

      expect(inRow('Lia', find.text('tempo indisponível')), findsOneWidget);
      expect(inRow('Lia', find.byType(StateModule)), findsNothing);

      await tester.tap(find.text('Entregar para Lia'));
      await pumpUntil(tester, () => h.services.appMode.mode is SharedKid);
      await tester.pumpAndSettle();
      expect(h.services.appMode.mode, const SharedKid('m1'));
    });

    for (final (what, json_) in [
      ('time_up', rulesJson(state: 'time_up', usedSeconds: 90 * 60)),
      ('all used', rulesJson(dailyMinutes: 30, usedSeconds: 30 * 60)),
    ]) {
      testWidgets('spent ($what), it reads "acabou o tempo de hoje", calm', (
        tester,
      ) async {
        await inicio(tester, rules: {'m1': () => json(200, json_)});

        final words = inRow('Lia', find.text('acabou o tempo de hoje'));
        expect(words, findsOneWidget);
        expect(modules(tester, 'Lia'), List.filled(5, true));
        expect(tester.widget<Text>(words).style?.color, Palette.light.muted);
        expect(inRow('Lia', find.byType(ErrorNote)), findsNothing);
      });
    }

    testWidgets('outside the hours, it says so beside the minutes', (
      tester,
    ) async {
      await inicio(
        tester,
        rules: {'m1': () => json(200, rulesJson(state: 'outside_window'))},
      );

      expect(
        inRow('Lia', find.text('40 de 90\u00a0min\u00a0· fora do horário')),
        findsOneWidget,
      );
    });
  });

  group('Entregar para {apelido}', () {
    testWidgets('hands the device to that child and the band grows into '
        'the child home', (tester) async {
      final h = await inicio(tester);

      await tester.tap(find.text('Entregar para Lia'));
      await pumpUntil(tester, () => h.services.appMode.mode is SharedKid);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        h.actions,
        contains('POST /v1/parental/kid-mode {"minor_id":"m1"}'),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is BandTransition && w.motion == BandMotion.grow,
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca');
      expect(find.byType(KidHomeScreen), findsOneWidget);
    });

    testWidgets('while it runs, its button is busy and the others wait', (
      tester,
    ) async {
      final gate = Completer<http.Response>();
      await inicio(tester, handOver: (_) => gate.future);

      await tester.tap(find.text('Entregar para Lia'));
      await tester.pump();

      PrimaryButton button(String name) => tester.widget<PrimaryButton>(
        find.byWidgetPredicate(
          (w) => w is PrimaryButton && w.label == 'Entregar para $name',
        ),
      );
      expect(button('Lia').busy, isTrue);
      expect(button('Téo').onPressed, isNull);
      gate.complete(problem(503, 'internal'));
      await tester.pumpAndSettle();
      expect(find.text(Copy.genericRetry), findsOneWidget);
      expect(button('Téo').onPressed, isNotNull);
    });

    testWidgets('pin_not_set leads to creating the PIN', (tester) async {
      final h = await inicio(
        tester,
        handOver: (_) => problem(409, 'pin_not_set'),
      );
      h.pinSet = false;

      await tapOn(tester, find.text('Entregar para Lia'));

      expect(h.location(tester), '/modo-crianca');
      final step = tester.widget<StepMarks>(find.byType(StepMarks));
      expect((step.step, step.of), (1, 2));
    });

    testWidgets('consent_required opens the child\'s new authorization, '
        'returning to the hand-over', (tester) async {
      final h = await inicio(
        tester,
        handOver: (_) => problem(403, 'consent_required'),
      );

      await tapOn(tester, find.text('Entregar para Lia'));

      final at = Uri.parse(h.location(tester));
      expect(at.path, '/familia/criancas/m1/autorizar');
      expect(at.queryParameters['depois'], '/modo-crianca/entregar');
      expect(find.byType(ReconsentScreen), findsOneWidget);
    });
  });

  testWidgets('"+ tempo" opens that child\'s more time, read by its name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = await inicio(tester);

    expect(find.bySemanticsLabel('Mais tempo para Téo'), findsOne);
    await tapOn(tester, inRow('Téo', find.text('+ tempo')));

    expect(h.location(tester), '/familia/tempo/m2/mais');
    semantics.dispose();
  });

  testWidgets('"Sugerir um vídeo" opens a new suggestion', (tester) async {
    final h = await inicio(tester);

    await tapOn(tester, find.text('Sugerir um vídeo'));

    expect(h.location(tester), '/sugestoes/nova');
  });

  testWidgets('with no child it says so and offers Cadastrar criança', (
    tester,
  ) async {
    final h = await inicio(tester, minors: []);

    expect(find.byType(ChildRow), findsNothing);
    expect(find.text('Nenhuma criança cadastrada ainda.'), findsOneWidget);
    await tapOn(
      tester,
      find.widgetWithText(PrimaryButton, 'Cadastrar criança'),
    );

    expect(h.location(tester), '/familia/criancas/nova');
  });

  testWidgets('it holds no door: the family\'s areas are under Família', (
    tester,
  ) async {
    await inicio(tester, roles: ['admin']);

    for (final title in [
      'Crianças',
      'Responsáveis',
      'Tempo de tela',
      'Sua conta',
      'Administração',
    ]) {
      expect(find.text(title), findsNothing, reason: title);
    }
    expect(find.text('Sair da conta'), findsNothing);
    expect(find.text('Excluir família'), findsNothing);
  });
}

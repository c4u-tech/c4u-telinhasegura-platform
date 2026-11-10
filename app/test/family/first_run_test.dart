import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/band_transition.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/pin_pad.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/consent.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/family/first_run.dart';
import 'package:telinha_segura/family/inicio.dart';
import 'package:telinha_segura/family/labels.dart';
import 'package:telinha_segura/family/reconsent_screen.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/kid_mode/hand_over_screen.dart' show ChildChoice;
import 'package:telinha_segura/kid_mode/link_code_screen.dart';
import 'package:telinha_segura/parental/app_mode.dart';
import 'package:telinha_segura/shell/guardian_shell.dart';

import '../access/harness.dart';
import '../parental/parental_api_test.dart' show profileJson;
import 'fixtures.dart';

final lia = minorJson('m1', 'Lia');
final teo = minorJson('m2', 'Téo', avatar: 'owl');

/// The guided first run at [initial] for a family holding [minors], with
/// or without a PIN. The API registers Lia (the family read then holds
/// her), saves the PIN and hands the device over, unless [handOver]
/// answers otherwise.
Future<Harness> firstRun(
  WidgetTester tester, {
  List<Map<String, Object?>> minors = const [],
  bool pinSet = false,
  String initial = '/comecar',
  Size size = const Size(390, 844),
  double textScale = 1,
  FutureOr<http.Response> Function(http.Request)? handOver,
}) async {
  late final Harness h;
  h =
      Harness(
          signedIn: true,
          api: (req) {
            final path = req.url.path;
            if (req.method == 'POST' && path == '/v1/family/minors') {
              h.family = familyWith([
                ...(h.family!['minors']! as List).cast<Map<String, Object?>>(),
                lia,
              ]);
              return json(201, lia);
            }
            if (req.method == 'PUT' && path == '/v1/parental/pin') {
              h.pinSet = true;
              return http.Response('', 204);
            }
            if (path == '/v1/parental/kid-mode') {
              if (handOver != null) return handOver(req);
              h.kidMode = {'minor_id': 'm1'};
              return http.Response('', 204);
            }
            if (path == '/v1/child/profile') return json(200, profileJson);
            return http.Response('', 204);
          },
        )
        ..family = familyWith(minors)
        ..pinSet = pinSet;
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: initial, size: size, textScale: textScale);
  return h;
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Taps a quiet action through its button: with real fonts its label is
/// narrower than the widget.
Future<void> tapQuiet(WidgetTester tester, String label) => tapOn(
  tester,
  find.descendant(
    of: find.widgetWithText(QuietAction, label),
    matching: find.byType(TextButton),
  ),
);

(int, int) marks(WidgetTester tester) {
  final m = tester.widget<StepMarks>(find.byType(StepMarks));
  return (m.step, m.of);
}

String title(WidgetTester tester) =>
    tester.widget<FieldLayout>(find.byType(FieldLayout).last).title;

Future<void> registerLia(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'Lia');
  await tester.pumpAndSettle();
  await tapOn(tester, find.byKey(const ValueKey(Avatar.fox)));
  await tapOn(tester, find.text(AgeBand.from5To8.label));
  await tapOn(tester, find.text('Continuar'));
  await tapOn(
    tester,
    find.widgetWithText(DeclarationRow, ConsentText.declaration),
  );
  await tapOn(tester, find.text('Cadastrar'));
}

Future<void> enterPin(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.ensureVisible(find.bySemanticsLabel(d));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(d));
    await tester.pump();
  }
  await tester.ensureVisible(find.bySemanticsLabel('Confirmar'));
  await tester.tap(find.bySemanticsLabel('Confirmar'));
  await tester.pumpAndSettle();
}

Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  group('after "Começar minha família"', () {
    testWidgets('the sun rises on the home, then the path opens at its '
        'first step', (tester) async {
      final h = Harness(
        signedIn: true,
        api: (req) {
          if (req.method == 'POST' && req.url.path == '/v1/family') {
            return json(201, familyWith([]));
          }
          return http.Response('', 204);
        },
      );
      await h.pump(tester);
      h.family = familyWith([]);

      await tester.tap(find.text('Começar minha família'));
      await tester.pump();
      await tester.pump();

      expect(h.location(tester), '/');
      expect(tester.widget<FieldLayout>(find.byType(FieldLayout)).rise, true);

      await tester.pump(FamilyHomeScreen.riseThenPath);
      await tester.pumpAndSettle();

      expect(h.location(tester), '/comecar');
      expect(find.byType(FirstRunScreen), findsOneWidget);
      expect(marks(tester), (1, 3));
    });

    testWidgets('joining a family by invitation stays on Início, with the '
        'resume row', (tester) async {
      late final Harness h;
      h = Harness(
        signedIn: true,
        api: (req) {
          if (req.url.path == '/v1/invitations') {
            return json(200, {
              'invitations': [receivedInvitation],
            });
          }
          if (req.method == 'POST' && req.url.path.endsWith('/accept')) {
            h.family = {
              ...familyWith([lia]),
              'role': 'guardian',
            };
            return json(200, h.family!);
          }
          return http.Response('', 204);
        },
      );
      await h.pump(tester);
      await tapOn(tester, find.text('Entrar na família'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
      expect(find.byType(FirstRunScreen), findsNothing);
      expect(find.text('Continuar: criar o PIN'), findsOneWidget);
    });
  });

  group('the path, from an empty family', () {
    testWidgets('walks child, PIN and hand-over in three numbered steps', (
      tester,
    ) async {
      final h = await firstRun(tester);

      expect(marks(tester), (1, 3));
      expect(title(tester), 'Cadastrar criança');
      await tester.enterText(find.byType(TextField), 'Lia');
      await tester.pumpAndSettle();
      await tapOn(tester, find.byKey(const ValueKey(Avatar.fox)));
      await tapOn(tester, find.text(AgeBand.from5To8.label));
      await tapOn(tester, find.text('Continuar'));

      // The consent is still the first step.
      expect(title(tester), 'Consentimento');
      expect(marks(tester), (1, 3));
      await tapOn(
        tester,
        find.widgetWithText(DeclarationRow, ConsentText.declaration),
      );
      await tapOn(tester, find.text('Cadastrar'));

      expect(
        h.actions.where((a) => a.startsWith('POST /v1/family/minors')),
        hasLength(1),
      );
      expect(marks(tester), (2, 3));
      expect(title(tester), 'Criar o PIN');
      expect(find.byType(PinPad), findsOneWidget);

      await enterPin(tester, '2580');
      await enterPin(tester, '2580');

      expect(h.actions, contains('PUT /v1/parental/pin {"pin":"2580"}'));
      expect(marks(tester), (3, 3));
      expect(title(tester), 'Tudo pronto');
      final avatar = tester.widget<AvatarDisc>(find.byType(AvatarDisc));
      expect(avatar.size, 96);
      expect(find.text('Lia'), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryButton, 'Entregar para Lia'),
        findsOneWidget,
      );
      expect(find.text('A criança tem o próprio aparelho?'), findsOneWidget);
      expect(find.widgetWithText(QuietAction, 'Vincular'), findsOneWidget);
      expect(h.location(tester), startsWith('/comecar'));
    });

    testWidgets('a PIN typed differently the second time starts over, as '
        'everywhere', (tester) async {
      final h = await firstRun(tester, minors: [lia]);

      await enterPin(tester, '2580');
      await enterPin(tester, '1111');

      expect(find.text('Os dois PINs não são iguais.'), findsOneWidget);
      expect(marks(tester), (2, 3));
      expect(h.actions.where((a) => a.startsWith('PUT')), isEmpty);
    });
  });

  group('a step the family already meets is skipped', () {
    testWidgets('with a child and no PIN it starts at the PIN', (tester) async {
      await firstRun(tester, minors: [lia]);

      expect(marks(tester), (2, 3));
      expect(find.byType(PinPad), findsOneWidget);
    });

    testWidgets('with a child and a PIN it is ready', (tester) async {
      await firstRun(tester, minors: [lia], pinSet: true);

      expect(marks(tester), (3, 3));
      expect(find.text('Entregar para Lia'), findsOneWidget);
    });

    testWidgets('with several children, the one just registered is the one '
        'handed the device', (tester) async {
      final h = await firstRun(tester);
      // Another adult registers Téo meanwhile.
      h.family = familyWith([teo]);

      await registerLia(tester);
      await enterPin(tester, '2580');
      await enterPin(tester, '2580');

      expect(marks(tester), (3, 3));
      expect(find.text('Entregar para Lia'), findsOneWidget);
      expect(find.byType(ChildChoice), findsNothing);
    });

    testWidgets('coming back to the last step names its child again', (
      tester,
    ) async {
      await firstRun(
        tester,
        minors: [lia, teo],
        pinSet: true,
        initial: '/comecar?crianca=m2',
      );

      expect(find.text('Entregar para Téo'), findsOneWidget);
      expect(find.byType(ChildChoice), findsNothing);
    });

    testWidgets('with several children and the child step skipped, the '
        'children are a choice of one', (tester) async {
      await firstRun(tester, minors: [lia, teo], pinSet: true);

      expect(marks(tester), (3, 3));
      expect(find.byType(ChildChoice), findsNWidgets(2));
      final button = find.byType(PrimaryButton);
      expect(tester.widget<PrimaryButton>(button).onPressed, isNull);

      await tapOn(tester, find.text('Téo'));

      expect(find.text('Entregar para Téo'), findsOneWidget);
    });
  });

  group('Entregar para {apelido}', () {
    testWidgets('hands the device over and the band grows into the child '
        'home', (tester) async {
      final h = await firstRun(tester, minors: [lia], pinSet: true);

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

    testWidgets('consent_required opens the child\'s new authorization, as '
        'today', (tester) async {
      final h = await firstRun(
        tester,
        minors: [lia],
        pinSet: true,
        handOver: (_) => problem(403, 'consent_required'),
      );

      await tapOn(tester, find.text('Entregar para Lia'));

      expect(
        Uri.parse(h.location(tester)).path,
        '/familia/criancas/m1/autorizar',
      );
      expect(find.byType(ReconsentScreen), findsOneWidget);
    });
  });

  testWidgets('Vincular opens the link code, whose back returns to the '
      'last step', (tester) async {
    final h = await firstRun(tester, minors: [lia, teo], pinSet: true);
    await tapOn(tester, find.text('Lia'));

    await tapQuiet(tester, 'Vincular');

    expect(Uri.parse(h.location(tester)).path, '/modo-crianca/vincular');
    expect(find.byType(LinkCodeScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Voltar').first);
    await tester.pumpAndSettle();

    expect(Uri.parse(h.location(tester)).path, '/comecar');
    expect(marks(tester), (3, 3));
  });

  testWidgets('the link code opened alone still returns to Modo criança', (
    tester,
  ) async {
    final h = await firstRun(
      tester,
      minors: [lia],
      pinSet: true,
      initial: '/modo-crianca/vincular',
    );

    await tester.tap(find.byTooltip('Voltar').first);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/modo-crianca');
  });

  testWidgets('the link code returns only into the path', (tester) async {
    final h = await firstRun(
      tester,
      minors: [lia],
      pinSet: true,
      initial: '/modo-crianca/vincular?depois=https://example.com',
    );

    await tester.tap(find.byTooltip('Voltar').first);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/modo-crianca');
  });

  group('Fazer depois', () {
    for (final (step, minors, pinSet, toConsent) in [
      (1, <Map<String, Object?>>[], false, false),
      (1, <Map<String, Object?>>[], false, true),
      (2, [lia], false, false),
      (3, [lia], true, false),
    ]) {
      testWidgets('on step $step${toConsent ? ' (consent)' : ''} returns to '
          'Início', (tester) async {
        final h = await firstRun(tester, minors: minors, pinSet: pinSet);
        if (toConsent) {
          await tester.enterText(find.byType(TextField), 'Lia');
          await tester.pumpAndSettle();
          await tapOn(tester, find.byKey(const ValueKey(Avatar.fox)));
          await tapOn(tester, find.text(AgeBand.from5To8.label));
          await tapOn(tester, find.text('Continuar'));
          expect(title(tester), 'Consentimento');
        }
        expect(marks(tester), (step, 3));

        await tapQuiet(tester, 'Fazer depois');

        expect(h.location(tester), '/');
        expect(find.byType(Inicio), findsOneWidget);
      });
    }
  });

  group('task depth', () {
    testWidgets('on a phone there is no bar', (tester) async {
      await firstRun(tester, minors: [lia], pinSet: true);

      expect(find.byKey(ShellBar.surfaceKey), findsNothing);
      expect(find.byTooltip('Voltar'), findsOneWidget);
    });

    testWidgets('on a wide window the rail stands beside it, on Início', (
      tester,
    ) async {
      await firstRun(
        tester,
        minors: [lia],
        pinSet: true,
        size: const Size(1280, 800),
      );

      final rail = tester.widget<InkRail>(find.byType(InkRail));
      expect(rail.selected, Destination.inicio);
      expect(find.text('Tudo pronto'), findsOneWidget);
    });

    testWidgets('back returns to Início', (tester) async {
      final h = await firstRun(tester, minors: [lia]);

      await tester.tap(find.byTooltip('Voltar').first);
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
    });
  });

  testWidgets('without a family it is the home\'s', (tester) async {
    final h = Harness(signedIn: true);
    await h.pump(tester, initial: '/comecar');

    expect(h.location(tester), '/');
  });

  group('Início\'s resume row', () {
    Future<Harness> inicio(
      WidgetTester tester,
      List<Map<String, Object?>> minors, {
      bool pinSet = false,
    }) => firstRun(tester, minors: minors, pinSet: pinSet, initial: '/');

    testWidgets('with no child it names registering one and opens the path '
        'there', (tester) async {
      final h = await inicio(tester, []);

      expect(find.text('Nenhuma criança cadastrada ainda.'), findsNothing);
      expect(find.byType(DoorRow), findsOneWidget);
      await tapOn(tester, find.text('Continuar: cadastrar uma criança'));

      expect(h.location(tester), '/comecar');
      expect(marks(tester), (1, 3));
    });

    testWidgets('with a child and no PIN it names the PIN and opens the '
        'path there, above the children', (tester) async {
      final h = await inicio(tester, [lia]);

      final resume = find.text('Continuar: criar o PIN');
      expect(resume, findsOneWidget);
      expect(find.byType(ChildRow), findsOneWidget);
      expect(
        tester.getRect(resume).bottom,
        lessThan(tester.getRect(find.byType(ChildRow)).top),
      );
      await tapOn(tester, resume);

      expect(h.location(tester), '/comecar');
      expect(marks(tester), (2, 3));
    });

    testWidgets('with a child and a PIN, Início is as built', (tester) async {
      await inicio(tester, [lia], pinSet: true);

      expect(find.textContaining('Continuar:'), findsNothing);
      expect(find.byType(DoorRow), findsNothing);
      expect(find.byType(ChildRow), findsOneWidget);
    });

    testWidgets('a failed PIN read says nothing', (tester) async {
      final h = Harness(signedIn: true)
        ..family = familyWith([lia])
        ..parentalRead = (_) => problem(503, 'internal');
      await h.pump(tester);

      expect(find.textContaining('Continuar:'), findsNothing);
      expect(find.byType(ChildRow), findsOneWidget);
    });
  });

  group('every step holds', () {
    for (final (name, minors, pinSet) in [
      ('step 1', <Map<String, Object?>>[], false),
      ('step 2', [lia], false),
      ('step 3', [lia], true),
      ('step 3, a choice', [lia, teo], true),
    ]) {
      for (final ground in [Brightness.light, Brightness.dark]) {
        testWidgets('$name on the ${ground.name} ground: contrast and '
            'targets', (tester) async {
          final semantics = tester.ensureSemantics();
          tester.platformDispatcher.platformBrightnessTestValue = ground;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await firstRun(tester, minors: minors, pinSet: pinSet);

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantics.dispose();
        });
      }

      testWidgets('$name at 200 % text on a 360 dp phone: no overflow, '
          'Fazer depois reachable', (tester) async {
        await firstRun(
          tester,
          minors: minors,
          pinSet: pinSet,
          size: const Size(360, 640),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Fazer depois'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

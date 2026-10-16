import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/band_transition.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/kid_mode/hand_over_screen.dart';
import 'package:telinha_segura/parental/app_mode.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import '../parental/parental_api_test.dart' show profileJson;

final twoChildren = [minorJson('m1', 'Lia'), minorJson('m2', 'Téo')];

/// `/modo-crianca/entregar` for a family holding [minors]; the hand-over
/// answers [answer] (204 by default, the session then locked).
Future<Harness> handOver(
  WidgetTester tester, {
  List<Map<String, Object?>>? minors,
  FutureOr<http.Response> Function(http.Request)? answer,
  bool reducedMotion = false,
  Size size = const Size(390, 844),
}) async {
  late final Harness h;
  h =
      Harness(
          signedIn: true,
          api: (req) {
            if (req.url.path == '/v1/parental/kid-mode') {
              if (answer != null) return answer(req);
              h.kidMode = {'minor_id': 'm1'};
              return http.Response('', 204);
            }
            if (req.url.path == '/v1/child/profile') {
              return json(200, profileJson);
            }
            return http.Response('', 204);
          },
        )
        ..family = familyWith(minors ?? twoChildren)
        ..pinSet = true;
  unawaited(h.services.familyModel.load());
  if (reducedMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await h.pump(tester, initial: '/modo-crianca/entregar', size: size);
  return h;
}

/// Choosing a child at 1440 × 900 moves nothing: the hint's place is
/// kept while it is hidden, and out of the semantics tree (fix round,
/// item 3).
Future<void> expectChoosingMovesNothing(
  WidgetTester tester,
  String title,
) async {
  final semantics = tester.ensureSemantics();
  const hint = 'Escolha uma criança acima.';
  final before = tester.getRect(find.text(title));
  expect(find.semantics.byLabel(hint), findsOneWidget);

  await tapOn(tester, find.text('Lia'));

  expect(tester.getRect(find.text(title)), before);
  expect(find.semantics.byLabel(hint), findsNothing);
  semantics.dispose();
}

Finder choice(String nickname) => find.bySemanticsLabel(nickname);

/// A radio read by the child's nickname.
Matcher chosen(String nickname, bool checked) => isSemantics(
  label: nickname,
  hasCheckedState: true,
  isChecked: checked,
  isInMutuallyExclusiveGroup: true,
  hasTapAction: true,
);

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Pumps a millisecond at a time (the scripted API answers on a timer)
/// until [done] holds.
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Finder get primary => find.byType(PrimaryButton);

void main() {
  testWidgets('at 1440 × 900 choosing a child keeps the title where it '
      'is (fix round, item 3)', (tester) async {
    await handOver(tester, size: const Size(1440, 900));
    await tester.pumpAndSettle();
    await expectChoosingMovesNothing(tester, 'Entregar este aparelho');
  });

  testWidgets('each child is a choice of one by nickname, none chosen, and '
      'the hand-over waits for one', (tester) async {
    final semantics = tester.ensureSemantics();
    await handOver(tester);

    expect(find.byType(HandOverScreen), findsOneWidget);
    expect(find.text('Entregar este aparelho'), findsOneWidget);
    for (final name in ['Lia', 'Téo']) {
      expect(find.text(name), findsOneWidget);
      expect(tester.getSemantics(choice(name)), chosen(name, false));
    }
    expect(find.textContaining('Entregar para'), findsNothing);
    expect(tester.widget<PrimaryButton>(primary).onPressed, isNull);
    semantics.dispose();
  });

  testWidgets('choosing a child offers "Entregar para {apelido}"', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = await handOver(tester);

    await tapOn(tester, find.text('Téo'));

    expect(tester.getSemantics(choice('Téo')), chosen('Téo', true));
    expect(tester.getSemantics(choice('Lia')), chosen('Lia', false));
    expect(find.text('Entregar para Téo'), findsOneWidget);
    expect(tester.widget<PrimaryButton>(primary).onPressed, isNotNull);
    expect(h.actions, isEmpty);
    semantics.dispose();
  });

  testWidgets('choosing a child moves nothing: every tile keeps the '
      "ring's room", (tester) async {
    await handOver(tester);
    Rect tile(String name) => tester.getRect(
      find.ancestor(of: find.text(name), matching: find.byType(ChildChoice)),
    );
    Rect disc(String name) => tester.getRect(
      find.descendant(
        of: find.ancestor(
          of: find.text(name),
          matching: find.byType(ChildChoice),
        ),
        matching: find.byType(AvatarDisc),
      ),
    );
    final before = {
      for (final name in ['Lia', 'Téo'])
        name: (tile(name), disc(name), tester.getRect(find.text(name))),
    };

    await tester.tap(find.text('Téo'));
    for (final ms in [0, 60, 120, 400]) {
      await tester.pump(Duration(milliseconds: ms));
      for (final name in ['Lia', 'Téo']) {
        expect(
          (tile(name), disc(name), tester.getRect(find.text(name))),
          before[name],
          reason: '$name at $ms ms',
        );
      }
    }
    for (final name in ['Lia', 'Téo']) {
      expect(
        (tile(name), disc(name), tester.getRect(find.text(name))),
        before[name],
        reason: name,
      );
    }
  });

  testWidgets('the hand-over locks the session and the band grows into the '
      'child home', (tester) async {
    final h = await handOver(tester);
    await tapOn(tester, find.text('Lia'));

    await tester.tap(find.text('Entregar para Lia'));
    // The call and the mode's move, then the route's first 100 ms.
    await pumpUntil(tester, () => h.services.appMode.mode is SharedKid);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(h.actions.first, 'POST /v1/parental/kid-mode {"minor_id":"m1"}');
    expect(h.services.appMode.mode, const SharedKid('m1'));
    final band = find.byWidgetPredicate(
      (w) => w is BandTransition && w.motion == BandMotion.grow,
    );
    expect(band, findsOneWidget);
    expect(
      find.descendant(of: band, matching: find.byType(ClipPath)),
      findsWidgets,
      reason: 'the band is still growing',
    );

    await tester.pumpAndSettle();
    expect(h.location(tester), '/crianca');
    expect(find.byType(KidHomeScreen), findsOneWidget);
  });

  testWidgets('under reduced motion the child home comes in a cut', (
    tester,
  ) async {
    final h = await handOver(tester, reducedMotion: true);
    await tapOn(tester, find.text('Lia'));

    await tester.tap(find.text('Entregar para Lia'));
    // The call and the mode's move, then the route's first 100 ms.
    await pumpUntil(tester, () => h.services.appMode.mode is SharedKid);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(KidHomeScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BandTransition),
        matching: find.byType(ClipPath),
      ),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(h.location(tester), '/crianca');
  });

  testWidgets('pin_not_set returns to the guide at Passo 1 de 2', (
    tester,
  ) async {
    final h = await handOver(
      tester,
      answer: (_) => problem(409, 'pin_not_set'),
    );
    h.pinSet = false;
    await tapOn(tester, find.text('Lia'));

    await tapOn(tester, find.text('Entregar para Lia'));

    expect(h.location(tester), '/modo-crianca');
    final step = tester.widget<StepMarks>(find.byType(StepMarks));
    expect((step.step, step.of), (1, 2));
    expect(h.services.appMode.mode, const Guardian());
  });

  testWidgets('not_found says the profile is gone and refreshes the '
      'children', (tester) async {
    final h = await handOver(tester, answer: (_) => problem(404, 'not_found'));
    await tapOn(tester, find.text('Lia'));
    final reads = h.calls.where((c) => c == 'GET /v1/family').length;
    h.family = familyWith([minorJson('m2', 'Téo')]);

    await tapOn(tester, find.text('Entregar para Lia'));

    expect(find.text(Copy.childGone), findsOneWidget);
    expect(find.byType(ErrorNote), findsOneWidget);
    expect(
      h.calls.where((c) => c == 'GET /v1/family').length,
      greaterThan(reads),
    );
    expect(find.text('Lia'), findsNothing);
    expect(find.text('Téo'), findsOneWidget);
    expect(find.textContaining('Entregar para'), findsNothing);
    expect(h.location(tester), '/modo-crianca/entregar');
  });

  testWidgets('a network failure keeps the choice and says to try again', (
    tester,
  ) async {
    final h = await handOver(tester, answer: (_) => problem(503, 'internal'));
    await tapOn(tester, find.text('Lia'));

    await tapOn(tester, find.text('Entregar para Lia'));

    expect(find.text(Copy.genericRetry), findsOneWidget);
    expect(find.text('Entregar para Lia'), findsOneWidget);
    expect(h.services.appMode.mode, const Guardian());
  });

  testWidgets('the hand-over disables its control while pending', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    final h = await handOver(tester, answer: (_) => gate.future);
    await tapOn(tester, find.text('Lia'));

    await tester.tap(find.text('Entregar para Lia'));
    await tester.pump();

    expect(tester.widget<PrimaryButton>(primary).busy, isTrue);
    gate.complete(problem(503, 'internal'));
    await tester.pumpAndSettle();
    expect(h.actions, ['POST /v1/parental/kid-mode {"minor_id":"m1"}']);
  });

  testWidgets('without children it sends to registering one first', (
    tester,
  ) async {
    await handOver(tester, minors: []);

    expect(find.textContaining('cadastre uma criança'), findsOneWidget);
  });
}

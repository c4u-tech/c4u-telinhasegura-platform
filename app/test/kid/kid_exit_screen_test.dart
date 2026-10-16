import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/design/band_transition.dart';
import 'package:telinha_segura/design/pin_pad.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/kid_exit_screen.dart';
import 'package:telinha_segura/kid/kid_layout.dart';
import 'package:telinha_segura/parental/app_mode.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import '../kid_mode/hand_over_screen_test.dart' show pumpUntil;
import '../kid_mode/set_pin_screen_test.dart'
    show expectNoteAbovePad, modules, padEnabled, type;

/// `/crianca/sair` on a shared device locked to Lia; the unlock answers
/// [answer] (204 by default, the lock then lifted).
Future<Harness> exitGate(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? answer,
  bool reducedMotion = false,
}) async {
  late final Harness h;
  h =
      Harness(
          signedIn: true,
          api: (req) {
            if (req.url.path == '/v1/child/unlock') {
              if (answer != null) return answer(req);
              h.kidMode = null;
              return http.Response('', 204);
            }
            return http.Response('', 204);
          },
        )
        ..kidMode = {'minor_id': 'm1'}
        ..family = ownerFamily;
  if (reducedMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await h.pump(tester, initial: '/crianca/sair');
  return h;
}

/// Types [digits] and confirms them, without settling.
Future<void> submit(WidgetTester tester, String digits) async {
  await type(tester, digits);
  await tester.ensureVisible(find.bySemanticsLabel('Confirmar'));
  await tester.tap(find.bySemanticsLabel('Confirmar'));
  await tester.pump();
}

Finder get closing => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is InkFieldPainter,
);

/// The quiet "Voltar" sits centred on the child side, its label centred
/// in its own target (fix round, item 3).
void expectCentredBack(WidgetTester tester, double width) {
  final button = tester.getRect(
    find.ancestor(of: find.text('Voltar'), matching: find.byType(TextButton)),
  );
  expect(button.center.dx, closeTo(width / 2, 0.5));
  expect(
    tester.getRect(find.text('Voltar')).center.dx,
    closeTo(button.center.dx, 0.5),
  );
}

void main() {
  testWidgets('asks the adult for the PIN on ink, with a quiet Voltar and '
      'no exit control', (tester) async {
    final semantics = tester.ensureSemantics();
    await exitGate(tester);

    expect(find.byType(KidExitScreen), findsOneWidget);
    expect(find.byType(KidLayout), findsOneWidget);
    expect(find.byType(HoldToExit), findsNothing);
    expect(find.byType(PinPad), findsOneWidget);
    expect(
      tester.getSemantics(find.text('PIN dos pais')),
      isSemantics(label: 'PIN dos pais', isHeader: true),
    );
    expect(find.widgetWithText(KidBack, 'Voltar'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the title and "Voltar" are centred, as the mark and the '
      'pad are (fix round, item 3)', (tester) async {
    await exitGate(tester);

    expect(
      tester.widget<Text>(find.text('PIN dos pais')).textAlign,
      TextAlign.center,
    );
    expectCentredBack(tester, 390);
  });

  testWidgets('Voltar returns to /crianca', (tester) async {
    final h = await exitGate(tester);

    await tester.ensureVisible(find.text('Voltar'));
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/crianca');
    expect(h.actions, isNot(contains(startsWith('POST'))));
  });

  testWidgets('the PIN unlocks and the screen closes back onto the band '
      'of the family home', (tester) async {
    final h = await exitGate(tester);

    await submit(tester, '2580');
    await pumpUntil(tester, () => h.services.appMode.mode is Guardian);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(h.actions, contains('POST /v1/child/unlock {"pin":"2580"}'));
    expect(
      find.byWidgetPredicate(
        (w) => w is BandTransition && w.motion == BandMotion.shrink,
      ),
      findsOneWidget,
    );
    expect(closing, findsOneWidget, reason: 'the ink is still closing');

    await tester.pumpAndSettle();
    expect(h.location(tester), '/');
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
    expect(closing, findsNothing);
  });

  testWidgets('mid-unlock the family home is painted once, steady and '
      'whole, under the opaque ink closing onto the band', (tester) async {
    final h = await exitGate(tester);

    await submit(tester, '2580');
    await pumpUntil(tester, () => h.services.appMode.mode is Guardian);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(closing, findsOneWidget, reason: 'the ink is still closing');
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
    expect(find.text('Sua família'), findsOneWidget);
    final title = tester.getRect(find.text('Sua família'));
    final home = find.byType(FamilyHomeScreen);
    expect(
      find.ancestor(
        of: home,
        matching: find.byWidgetPredicate(
          (w) =>
              (w is FadeTransition && w.opacity.value < 1) ||
              (w is Opacity && w.opacity < 1) ||
              (w is SlideTransition && w.position.value != Offset.zero) ||
              (w is ScaleTransition && w.scale.value != 1) ||
              w is ClipPath,
        ),
      ),
      findsNothing,
      reason: 'the page underneath is neither faded, moved nor clipped',
    );
    expect(
      tester.renderObject(closing),
      paints..rrect(color: BrandColors.ink),
      reason: 'the closing field is the opaque brand ink',
    );
    expect(BrandColors.ink.a, 1.0);

    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Sua família')), title);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('under reduced motion the family home comes in a cut', (
    tester,
  ) async {
    final h = await exitGate(tester, reducedMotion: true);

    await submit(tester, '2580');
    await pumpUntil(tester, () => h.services.appMode.mode is Guardian);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(FamilyHomeScreen), findsOneWidget);
    expect(closing, findsNothing);
    await tester.pumpAndSettle();
    expect(h.location(tester), '/');
  });

  testWidgets('any other way home is the ordinary page', (tester) async {
    final h = Harness(signedIn: true)..family = ownerFamily;
    await h.pump(tester, initial: '/familia/criancas');

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(BandTransition), findsNothing);
    await tester.pumpAndSettle();
    expect(h.location(tester), '/');
  });

  testWidgets('a wrong PIN says so, empties the modules and keeps the pad', (
    tester,
  ) async {
    final h = await exitGate(
      tester,
      answer: (_) => problem(403, 'invalid_pin'),
    );

    await submit(tester, '1111');
    await tester.pumpAndSettle();

    expect(find.text('PIN errado. Tente de novo.'), findsOneWidget);
    expect(find.byType(ErrorNote), findsOneWidget);
    expectNoteAbovePad(tester, find.text('PIN dos pais'));
    expect(modules(tester), List.filled(6, false));
    expect(padEnabled(tester), isTrue);
    expect(h.location(tester), '/crianca/sair');
    expect(h.services.appMode.mode, const SharedKid('m1'));
  });

  testWidgets('rate_limited disables the pad while the time left counts '
      'down', (tester) async {
    await exitGate(
      tester,
      answer: (_) =>
          problem(429, 'rate_limited', headers: {'retry-after': '30'}),
    );

    await submit(tester, '1111');
    await pumpUntil(
      tester,
      () => find.textContaining('Muitas tentativas').evaluate().isNotEmpty,
    );

    expect(find.textContaining('30 s'), findsOneWidget);
    expect(padEnabled(tester), isFalse);
    expect(modules(tester), List.filled(6, false));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('29 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 29));
    expect(padEnabled(tester), isTrue);
  });

  testWidgets('the pad waits while the check is pending', (tester) async {
    final gate = Completer<http.Response>();
    await exitGate(tester, answer: (_) => gate.future);

    await submit(tester, '2580');
    await tester.pump(const Duration(milliseconds: 10));

    expect(padEnabled(tester), isFalse);
    gate.complete(problem(503, 'internal'));
    await tester.pumpAndSettle();
    expect(find.text(Copy.genericRetry), findsOneWidget);
    expect(padEnabled(tester), isTrue);
  });

  testWidgets('an unlock that ends the session lands on the entry screen '
      'with a calm notice that the family no longer exists', (tester) async {
    late final Harness h;
    h = await exitGate(
      tester,
      answer: (_) {
        h.signedIn = false;
        return problem(401, 'unauthenticated');
      },
    );

    await submit(tester, '2580');
    await tester.pumpAndSettle();

    expect(h.services.client.status.value, AuthStatus.signedOut);
    expect(h.location(tester), '/entrar');
    expect(find.byType(EntryScreen), findsOneWidget);
    expect(find.widgetWithText(Notice, Copy.familyGone), findsOneWidget);
    expect(find.byType(ErrorNote), findsNothing);
  });

  testWidgets('the entry screen shows the notice once', (tester) async {
    late final Harness h;
    h = await exitGate(
      tester,
      answer: (_) {
        h.signedIn = false;
        return problem(401, 'unauthenticated');
      },
    );
    await submit(tester, '2580');
    await tester.pumpAndSettle();

    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/criar-conta');
    await tester.pumpAndSettle();
    router.go('/entrar');
    await tester.pumpAndSettle();

    expect(find.text(Copy.familyGone), findsNothing);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/family/profile_fields.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../design/pump.dart' show findAddress;
import 'fixtures.dart';
import 'invitations_test.dart' show inDays;

Map<String, Object?> received(String id, String inviter, {int days = 5}) => {
  'id': id,
  'inviter_email': inviter,
  'expires_at': inDays(days),
};

/// The first use of an account that [invitations] wait for, every other
/// request answered by [other].
Future<Harness> firstUse(
  WidgetTester tester,
  List<Map<String, Object?>> Function() invitations, {
  FutureOr<http.Response> Function(http.Request)? other,
}) async {
  final h = Harness(
    signedIn: true,
    api: (req) => req.url.path == '/v1/invitations'
        ? json(200, {'invitations': invitations()})
        : (other ?? (_) => http.Response('', 204))(req),
  )..family = null;
  await h.pump(tester, initial: '/');
  await tester.pumpAndSettle();
  return h;
}

void main() {
  group('one invitation', () {
    testWidgets('leads the first use, with who invited and until when', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await firstUse(tester, () => [received('i1', 'carla@example.com')]);

      expect(
        tester.widget<FieldLayout>(find.byType(FieldLayout)).title,
        'Você tem um\u00a0convite',
      );
      expect(
        find.text(
          'Entre para cuidar das crianças junto com quem convidou você.',
        ),
        findsOneWidget,
      );
      expect(findAddress('carla@example.com'), findsWidgets);
      expect(find.text('convidou você · expira em 5 dias'), findsOneWidget);
      // A read row, not a choice.
      expect(find.byType(SelectableRow), findsNothing);
      expect(find.text('Tenho um convite'), findsNothing);
      expect(find.byType(CapacityRow), findsNothing);
      expect(find.text('Prefere começar a sua?'), findsOneWidget);
      expect(find.text('Começar minha família'), findsOneWidget);
      final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(button.label, 'Entrar na família');
      expect(button.onPressed, isNotNull);
      semantics.dispose();
    });

    testWidgets('Entrar na família joins it and the sun rises', (tester) async {
      final h = await firstUse(
        tester,
        () => [received('i1', 'carla@example.com')],
        other: (_) => json(200, ownerFamily),
      );

      await tester.tap(find.text('Entrar na família'));
      await tester.pumpAndSettle();

      expect(h.actions, ['POST /v1/invitations/i1/accept']);
      expect(find.widgetWithText(DoorRow, 'Crianças'), findsOneWidget);
      expect(tester.widget<FieldLayout>(find.byType(FieldLayout)).rise, true);
    });

    testWidgets('an erased inviter reads as a family', (tester) async {
      await firstUse(tester, () => [received('i1', '')]);

      expect(find.text('Uma família'), findsOneWidget);
      expect(find.text('convidou você · expira em 5 dias'), findsOneWidget);
    });

    testWidgets('among several, an erased inviter reads in sentence case', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await firstUse(
        tester,
        () => [received('i2', ''), received('i1', 'carla@example.com')],
      );

      expect(find.text('Uma família'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Convite de uma família, expira em 5 dias'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('while joining, the button is busy and nothing else acts', (
      tester,
    ) async {
      final answer = Completer<http.Response>();
      await firstUse(
        tester,
        () => [received('i1', 'carla@example.com')],
        other: (_) => answer.future,
      );

      await tester.tap(find.text('Entrar na família'));
      await tester.pump();

      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).busy,
        true,
      );
      final start = tester.widget<QuietAction>(
        find.widgetWithText(QuietAction, 'Começar minha família'),
      );
      expect(start.onPressed, isNull);

      answer.complete(json(200, ownerFamily));
      await tester.pumpAndSettle();
    });

    testWidgets('Começar minha família still starts one', (tester) async {
      final h = await firstUse(
        tester,
        () => [received('i1', 'carla@example.com')],
        other: (_) => json(201, ownerFamily),
      );

      await tester.tap(find.text('Começar minha família'));
      await tester.pumpAndSettle();

      expect(h.actions, ['POST /v1/family']);
      expect(find.widgetWithText(DoorRow, 'Crianças'), findsOneWidget);
    });
  });

  group('several invitations', () {
    testWidgets('are a choice of one, none chosen, the button waiting', (
      tester,
    ) async {
      await firstUse(
        tester,
        () => [
          received('i2', 'davi@example.com', days: 1),
          received('i1', 'carla@example.com'),
        ],
      );

      expect(
        tester.widget<FieldLayout>(find.byType(FieldLayout)).title,
        'Você tem 2\u00a0convites',
      );
      final rows = tester.widgetList<SelectableRow>(find.byType(SelectableRow));
      expect(rows.map((r) => r.selected), [false, false]);
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNull,
      );
      expect(find.text('Escolha um convite acima.'), findsOneWidget);
      expect(find.text('convidou você · expira amanhã'), findsOneWidget);
    });

    testWidgets('each reads as a radio with its inviter and expiry', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await firstUse(
        tester,
        () => [
          received('i2', 'davi@example.com', days: 1),
          received('i1', 'carla@example.com'),
        ],
      );

      expect(
        find.bySemanticsLabel('Convite de carla@example.com, expira em 5 dias'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byType(SelectableRow).last),
        matchesSemantics(
          label: 'Convite de carla@example.com, expira em 5 dias',
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the chosen one is the one joined', (tester) async {
      final h = await firstUse(
        tester,
        () => [
          received('i2', 'davi@example.com', days: 1),
          received('i1', 'carla@example.com'),
        ],
        other: (_) => json(200, ownerFamily),
      );

      await tester.tap(find.byType(SelectableRow).last);
      await tester.pump();
      expect(
        tester
            .widgetList<SelectableRow>(find.byType(SelectableRow))
            .map((r) => r.selected),
        [false, true],
      );
      // Hidden, its place kept: nothing moves.
      expect(tester.widget<SubmitHint>(find.byType(SubmitHint)).visible, false);

      await tester.tap(find.text('Entrar na família'));
      await tester.pumpAndSettle();

      expect(h.actions, ['POST /v1/invitations/i1/accept']);
    });
  });

  group('refusals', () {
    testWidgets('a gone invitation says so, and the plain first use keeps '
        'the words when none is left', (tester) async {
      var waiting = [received('i1', 'carla@example.com')];
      await firstUse(
        tester,
        () => waiting,
        other: (_) {
          waiting = [];
          return problem(404, 'invitation_unavailable');
        },
      );

      await tester.tap(find.text('Entrar na família'));
      await tester.pumpAndSettle();

      expect(find.text(Copy.invitationGone), findsOneWidget);
      expect(find.text('Tenho um convite'), findsOneWidget);
      expect(
        tester.widget<FieldLayout>(find.byType(FieldLayout)).title,
        'Sua família',
      );
    });

    testWidgets('a gone chosen invitation clears the choice', (tester) async {
      var waiting = [
        received('i2', 'davi@example.com', days: 1),
        received('i1', 'carla@example.com'),
        received('i3', 'eva@example.com'),
      ];
      await firstUse(
        tester,
        () => waiting,
        other: (_) {
          waiting = [waiting.first, waiting.last];
          return problem(404, 'invitation_unavailable');
        },
      );

      await tester.tap(find.byType(SelectableRow).at(1));
      await tester.pump();
      await tester.tap(find.text('Entrar na família'));
      await tester.pumpAndSettle();

      expect(find.text(Copy.invitationGone), findsOneWidget);
      final rows = tester.widgetList<SelectableRow>(find.byType(SelectableRow));
      expect(rows.map((r) => r.selected), [false, false]);
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNull,
      );
    });

    testWidgets('a full family says so and the invitation stays', (
      tester,
    ) async {
      await firstUse(
        tester,
        () => [received('i1', 'carla@example.com')],
        other: (_) => problem(409, 'limit_reached'),
      );

      await tester.tap(find.text('Entrar na família'));
      await tester.pumpAndSettle();

      expect(find.text(Copy.invitationFamilyFull), findsOneWidget);
      expect(find.text('convidou você · expira em 5 dias'), findsOneWidget);
    });
  });

  testWidgets('a list that fails to come leaves the plain first use', (
    tester,
  ) async {
    final h = Harness(
      signedIn: true,
      api: (req) => req.url.path == '/v1/invitations'
          ? problem(503, 'unavailable')
          : http.Response('', 204),
    )..family = null;
    await h.pump(tester, initial: '/');
    await tester.pumpAndSettle();

    expect(find.text('Tenho um convite'), findsOneWidget);
    expect(find.byType(ErrorNote), findsNothing);
  });
}

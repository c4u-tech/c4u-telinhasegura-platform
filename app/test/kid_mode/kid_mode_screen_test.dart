import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/kid_mode/kid_mode_screen.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import '../parental/parental_api_test.dart' show deviceJson;

final twoChildren = [minorJson('m1', 'Lia'), minorJson('m2', 'Téo')];

/// `/modo-crianca` for a family holding [minors], with or without a PIN.
Future<Harness> kidMode(
  WidgetTester tester, {
  bool pinSet = false,
  int devices = 0,
  List<Map<String, Object?>>? minors,
  FutureOr<http.Response> Function(http.Request)? read,
  Object? extra,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final h = Harness(signedIn: true)
    ..family = familyWith(minors ?? twoChildren)
    ..pinSet = pinSet
    ..linkedDevices = [
      for (var i = 0; i < devices; i++) {...deviceJson, 'id': 'd$i'},
    ]
    ..parentalRead = read;
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: '/', size: size, textScale: textScale);
  GoRouter.of(tester.element(find.byType(Scaffold).first))
      .go('/modo-crianca', extra: extra);
  await tester.pumpAndSettle();
  return h;
}

Finder door(String title) => find.widgetWithText(DoorRow, title);

Future<void> open(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('the guide, without a PIN', () {
    testWidgets('shows Passo 1 de 2, what the PIN is for, and Criar o PIN', (
      tester,
    ) async {
      await kidMode(tester);

      expect(find.text('Modo criança'), findsOneWidget);
      final step = tester.widget<StepMarks>(find.byType(StepMarks));
      expect((step.step, step.of), (1, 2));
      expect(find.textContaining('só um adulto com ele'), findsOneWidget);
      expect(find.widgetWithText(PrimaryButton, 'Criar o PIN'), findsOne);
      expect(find.byType(DoorRow), findsNothing);
    });

    testWidgets('Criar o PIN opens /modo-crianca/pin', (tester) async {
      final h = await kidMode(tester);

      await open(tester, find.text('Criar o PIN'));

      expect(h.location(tester), '/modo-crianca/pin');
    });

    testWidgets('back from a PIN just created: Passo 2 de 2 with the two '
        'moves, the sun rising and the adults told', (tester) async {
      final h = await kidMode(tester, pinSet: true, extra: PinSaved.created);

      final step = tester.widget<StepMarks>(find.byType(StepMarks));
      expect((step.step, step.of), (2, 2));
      expect(find.byType(DoorRow), findsNWidgets(2));
      expect(door('Entregar este aparelho'), findsOne);
      expect(door('Vincular o aparelho da criança'), findsOne);
      expect(door('Trocar o PIN'), findsNothing);
      expect(tester.widget<FieldLayout>(find.byType(FieldLayout)).rise, true);
      expect(find.textContaining('Avisamos por e-⁠mail'), findsOne);

      await open(tester, door('Entregar este aparelho'));
      expect(h.location(tester), '/modo-crianca/entregar');
    });

    testWidgets('alone in the family, nobody else is said to be told', (
      tester,
    ) async {
      final h = Harness(signedIn: true)
        ..family = {
          ...familyWith(twoChildren),
          'members': [(ownerFamily['members']! as List).first],
          'pending_invitations': 0,
        }
        ..pinSet = true;
      unawaited(h.services.familyModel.load());
      await h.pump(tester, initial: '/');
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go('/modo-crianca', extra: PinSaved.created);
      await tester.pumpAndSettle();

      expect(find.text('PIN criado.'), findsOne);
      expect(find.textContaining('Avisamos'), findsNothing);
    });
  });

  group('the index, with a PIN', () {
    testWidgets('shows the four doors, the children beneath the first', (
      tester,
    ) async {
      await kidMode(tester, pinSet: true, devices: 2);

      expect(find.byType(StepMarks), findsNothing);
      expect(
        tester.widgetList<DoorRow>(find.byType(DoorRow)).map((d) => d.title),
        [
          'Entregar este aparelho',
          'Vincular o aparelho da criança',
          'Aparelhos vinculados',
          'Trocar o PIN',
        ],
      );
      expect(
        find.descendant(
          of: door('Entregar este aparelho'),
          matching: find.byType(AvatarDisc),
        ),
        findsNWidgets(2),
      );
      final capacity = tester.widget<CapacityRow>(find.byType(CapacityRow));
      expect(
        (capacity.filled, capacity.total, capacity.words),
        (2, 10, '2 de 10 aparelhos'),
      );
    });

    testWidgets('each door reads what it shows', (tester) async {
      final semantics = tester.ensureSemantics();
      await kidMode(tester, pinSet: true, devices: 2);

      for (final label in [
        'Entregar este aparelho, para Lia e Téo',
        'Aparelhos vinculados, 2 de 10 aparelhos',
        'Vincular o aparelho da criança',
        'Trocar o PIN',
      ]) {
        expect(find.bySemanticsLabel(label), findsOne, reason: label);
      }
      semantics.dispose();
    });

    for (final (title, path) in [
      ('Entregar este aparelho', '/modo-crianca/entregar'),
      ('Vincular o aparelho da criança', '/modo-crianca/vincular'),
      ('Aparelhos vinculados', '/modo-crianca/aparelhos'),
      ('Trocar o PIN', '/modo-crianca/pin'),
    ]) {
      testWidgets('$title opens $path', (tester) async {
        final h = await kidMode(tester, pinSet: true);

        await open(tester, door(title));

        expect(h.location(tester), path);
      });
    }

    testWidgets('a PIN changed shows the index with the sun rising and the '
        'adults told', (tester) async {
      await kidMode(tester, pinSet: true, extra: PinSaved.changed);

      expect(find.byType(StepMarks), findsNothing);
      expect(door('Trocar o PIN'), findsOne);
      expect(tester.widget<FieldLayout>(find.byType(FieldLayout)).rise, true);
      expect(find.textContaining('PIN trocado.'), findsOne);
    });
  });

  group('no children', () {
    for (final (pinSet, extra) in [(true, null), (true, PinSaved.created)]) {
      testWidgets('the first two doors say a child comes first and open '
          '/familia/criancas/nova${extra == null ? '' : ' (guide)'}', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final h = await kidMode(
          tester,
          pinSet: pinSet,
          minors: [],
          extra: extra,
        );

        for (final title in [
          'Entregar este aparelho',
          'Vincular o aparelho da criança',
        ]) {
          expect(
            find.descendant(of: door(title), matching: find.text(childFirst)),
            findsOne,
            reason: title,
          );
          expect(
            find.bySemanticsLabel('$title, $childFirst'),
            findsOne,
            reason: title,
          );
        }
        await open(tester, door('Vincular o aparelho da criança'));
        expect(h.location(tester), '/familia/criancas/nova');
        semantics.dispose();
      });
    }
  });

  group('loading and failure', () {
    testWidgets('placeholder rows while the state is read, not a spinner', (
      tester,
    ) async {
      final answer = Completer<http.Response>();
      await kidMode(tester, read: (_) => answer.future);

      expect(find.byType(FamilyPlaceholder), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Criar o PIN'), findsNothing);

      answer.complete(json(200, {'set': false, 'devices': <Object>[]}));
      await tester.pumpAndSettle();
      expect(find.byType(FamilyPlaceholder), findsNothing);
      expect(find.text('Criar o PIN'), findsOne);
    });

    testWidgets('a failed read offers Tentar de novo, which reads again', (
      tester,
    ) async {
      var fail = true;
      final h = await kidMode(
        tester,
        read: (req) => fail
            ? problem(503, 'unavailable')
            : req.url.path.endsWith('/pin')
            ? json(200, {'set': true})
            : json(200, {'devices': <Object>[]}),
      );

      expect(find.byType(ErrorNote), findsOneWidget);
      fail = false;
      await open(tester, find.text('Tentar de novo'));

      expect(find.byType(ErrorNote), findsNothing);
      expect(door('Trocar o PIN'), findsOne);
      expect(
        h.calls.where((c) => c == 'GET /v1/parental/pin'),
        hasLength(greaterThanOrEqualTo(2)),
      );
    });

    testWidgets('no_family leaves for the home, which says why', (
      tester,
    ) async {
      // Answered once the home has left, as over a network.
      final h = await kidMode(
        tester,
        read: (_) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return problem(404, 'no_family');
        },
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
      expect(find.text('Você não faz mais parte desta família.'), findsOne);
    });
  });

  testWidgets('back returns to the family home', (tester) async {
    final h = await kidMode(tester, pinSet: true);

    await open(tester, find.byTooltip('Voltar'));

    expect(h.location(tester), '/');
  });

  testWidgets('coming back from a kid-mode screen reads the state again, '
      'quietly', (tester) async {
    final h = await kidMode(tester, pinSet: true);
    await open(tester, door('Entregar este aparelho'));
    expect(h.location(tester), '/modo-crianca/entregar');

    h.pinSet = false; // the PIN went meanwhile
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/modo-crianca');
    await tester.pump();
    expect(find.byType(FamilyPlaceholder), findsNothing);
    await tester.pumpAndSettle();

    final step = tester.widget<StepMarks>(find.byType(StepMarks));
    expect((step.step, step.of), (1, 2));
  });
}

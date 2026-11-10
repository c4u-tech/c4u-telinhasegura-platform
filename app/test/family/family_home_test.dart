import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/family/inicio.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/a11y_test.dart' show invitationsFor;
import '../access/harness.dart';
import 'fixtures.dart';

final guardianFamily = <String, Object?>{
  ...ownerFamily,
  'role': 'guardian',
  'invitations': null,
};

Future<Harness> home(
  WidgetTester tester, {
  Map<String, Object?>? family = ownerFamily,
  FutureOr<http.Response> Function(http.Request)? api,
  bool unverified = false,
  List<String> roles = const [],
  bool pinSet = true,
}) async {
  final h = Harness(signedIn: true, api: api)
    ..family = family
    ..unverified = unverified
    ..roles = roles
    ..pinSet = pinSet;
  await h.pump(tester, initial: '/');
  return h;
}

void main() {
  group('the family\'s doors', () {
    testWidgets('are not in the pre-family states: Família holds them once '
        'the family is ready', (tester) async {
      await home(tester, family: null);

      for (final title in [
        'Crianças',
        'Responsáveis',
        'Modo criança',
        'Tempo de tela',
        'Vídeos',
        'Sugerir vídeo',
      ]) {
        expect(
          find.widgetWithText(DoorRow, title),
          findsNothing,
          reason: title,
        );
      }
    });

    testWidgets('with a family, the home is Início, holding no door', (
      tester,
    ) async {
      await home(tester, roles: ['admin', 'curator']);

      expect(find.byType(Inicio), findsOneWidget);
      expect(find.byType(DoorRow), findsNothing);
      expect(find.text('Sair da conta'), findsNothing);
    });
  });

  group('the Sua conta door', () {
    Finder accountDoor() => find.widgetWithText(DoorRow, 'Sua conta');

    final states = <String, (Map<String, Object?>?, bool)>{
      'no family': (null, false),
      'the email unverified': (null, true),
    };

    for (final MapEntry(key: state, value: (family, unverified))
        in states.entries) {
      testWidgets('with $state, it shows the account\'s email and opens '
          '/conta', (tester) async {
        final semantics = tester.ensureSemantics();
        final h = await home(tester, family: family, unverified: unverified);

        expect(accountDoor(), findsOneWidget);
        expect(
          find.descendant(
            of: accountDoor(),
            matching: find.text(addressBreaks('ana@example.com')),
          ),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Sua conta, ana@example.com'), findsOne);
        await tester.ensureVisible(accountDoor());
        await tester.pumpAndSettle();
        await tester.tap(accountDoor());
        await tester.pumpAndSettle();

        expect(h.location(tester), '/conta');
        semantics.dispose();
      });
    }

    testWidgets('with a family it is gone: Conta holds the account', (
      tester,
    ) async {
      await home(tester);

      expect(accountDoor(), findsNothing);
    });

    for (final (state, unverified, action) in [
      ('no family', false, 'Tenho um convite'),
      ('the email unverified', true, 'Reenviar e-\u2060mail'),
    ]) {
      testWidgets('with $state, it sits below the state\'s choice and above '
          'Sair da conta', (tester) async {
        await home(tester, family: null, unverified: unverified);

        final door = accountDoor();
        expect(
          tester.getTopLeft(door).dy,
          greaterThan(tester.getBottomLeft(find.text(action)).dy),
        );
        expect(
          tester.getBottomLeft(door).dy,
          lessThan(tester.getTopLeft(find.text('Sair da conta')).dy),
        );
      });
    }
  });

  group('first use', () {
    testWidgets('no family offers the explicit choice', (tester) async {
      await home(tester, family: null);

      expect(find.text('Começar minha família'), findsOneWidget);
      expect(find.text('Tenho um convite'), findsOneWidget);
      // Only the account's own door.
      expect(
        tester.widgetList<DoorRow>(find.byType(DoorRow)).map((d) => d.title),
        ['Sua conta'],
      );
    });

    testWidgets('shows the bounded set, hollow, read by its words only', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await home(tester, family: null);

      final capacities = tester.widgetList<CapacityRow>(
        find.byType(CapacityRow),
      );
      expect(capacities.map((c) => (c.filled, c.total, c.words)), [
        (0, 10, 'Cabem até 10 crianças'),
        (0, 6, 'e até 6 adultos'),
      ]);
      expect(find.bySemanticsLabel('Cabem até 10 crianças'), findsOne);
      expect(find.bySemanticsLabel('e até 6 adultos'), findsOne);
      // Under the explanatory text, above the choice.
      final rows = find.byType(CapacityRow);
      expect(
        tester.getTopLeft(rows.first).dy,
        greaterThan(tester.getBottomLeft(find.textContaining('Comece')).dy),
      );
      expect(
        tester.getBottomLeft(rows.last).dy,
        lessThan(tester.getTopLeft(find.byType(PrimaryButton)).dy),
      );
      semantics.dispose();
    });

    testWidgets('Começar minha família creates it and the sun rises', (
      tester,
    ) async {
      final h = await home(
        tester,
        family: null,
        api: (_) => json(201, ownerFamily),
      );
      expect(tester.widget<FieldLayout>(find.byType(FieldLayout)).rise, false);

      await tester.tap(find.text('Começar minha família'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Then Início reads the new family's child's day, the sun rising,
      // before the first run opens.
      expect(h.actions.first, 'POST /v1/family');
      expect(h.actions.where((a) => a.startsWith('POST')), ['POST /v1/family']);
      expect(find.byType(Inicio), findsOneWidget);
      expect(tester.widget<FieldLayout>(find.byType(FieldLayout)).rise, true);

      await tester.pumpAndSettle();
      expect(h.location(tester), '/comecar');
    });

    testWidgets('creating disables the button while pending, and a dropped '
        'connection keeps the choice', (tester) async {
      final answer = Completer<http.Response>();
      final h = await home(tester, family: null, api: (_) => answer.future);

      await tester.tap(find.text('Começar minha família'));
      await tester.pump();
      final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(button.busy, isTrue);

      answer.completeError(http.ClientException('down'));
      await tester.pumpAndSettle();

      expect(h.actions, ['POST /v1/family']);
      expect(find.byType(ErrorNote), findsOneWidget);
      expect(find.text('Começar minha família'), findsOneWidget);
    });

    testWidgets('Tenho um convite explains where the invitation arrives and '
        'creates nothing', (tester) async {
      final h = await home(tester, family: null);

      await tester.tap(find.text('Tenho um convite'));
      await tester.pumpAndSettle();

      expect(find.textContaining('e-\u2060mail'), findsWidgets);
      expect(find.textContaining('link'), findsOneWidget);
      expect(h.actions, isEmpty);
    });

    testWidgets('after losing the family elsewhere, the choice comes with a '
        'calm notice', (tester) async {
      final h = Harness(signedIn: true)..family = ownerFamily;
      unawaited(h.services.familyModel.load());
      await h.pump(tester, initial: '/familia/responsaveis');

      h.services.familyModel.absorb(
        const ApiError(status: 404, code: 'no_family'),
      );
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
      expect(find.text('Você não faz mais parte desta família.'), findsOne);
      expect(find.text('Começar minha família'), findsOneWidget);
    });
  });

  group('email unverified', () {
    testWidgets('the account shows the verify prompt, not the choice, and '
        'resends', (tester) async {
      final h = await home(
        tester,
        family: null,
        unverified: true,
        api: (_) => http.Response('', 202),
      );

      expect(find.text('Começar minha família'), findsNothing);
      expect(find.text(addressBreaks('ana@example.com')), findsWidgets);
      await tester.tap(find.text('Reenviar e-\u2060mail'));
      await tester.pumpAndSettle();

      expect(h.actions, [
        'POST /v1/email-verifications {"email":"ana@example.com"}',
      ]);
      expect(h.calls, isNot(contains('GET /v1/family')));
    });

    testWidgets('a family read answering email_unverified shows the same '
        'prompt', (tester) async {
      final h = Harness(signedIn: true)
        ..familyRead = () => problem(403, 'email_unverified');
      await h.pump(tester, initial: '/');

      expect(find.text('Reenviar e-\u2060mail'), findsOneWidget);
    });

    testWidgets('coming back after confirming reads the account again', (
      tester,
    ) async {
      final h = Harness(signedIn: true)..unverified = true;
      await h.pump(tester, initial: '/');
      expect(find.text('Reenviar e-\u2060mail'), findsOneWidget);

      h.unverified = false;
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go('/esqueci-a-senha');
      await tester.pumpAndSettle();
      router.go('/');
      await tester.pumpAndSettle();

      expect(find.text('Começar minha família'), findsOneWidget);
    });
  });

  group('loading and failure', () {
    testWidgets('placeholder rows while the family loads, not a spinner', (
      tester,
    ) async {
      final answer = Completer<http.Response>();
      final h = Harness(signedIn: true)..familyRead = () => answer.future;
      await h.pump(tester, initial: '/');

      expect(find.byKey(const Key('family-placeholder')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      answer.complete(json(200, ownerFamily));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('family-placeholder')), findsNothing);
      expect(find.byType(ChildRow), findsOneWidget);
    });

    testWidgets('a failed load offers Tentar de novo', (tester) async {
      var fail = true;
      final h = Harness(signedIn: true)
        ..familyRead = () =>
            fail ? problem(503, 'unavailable') : json(200, ownerFamily);
      await h.pump(tester, initial: '/');

      expect(find.byType(ErrorNote), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorNote), findsNothing);
      expect(find.byType(ChildRow), findsOneWidget);
    });
  });

  group('Sair da conta', () {
    // The "Sua conta" door names the account; the foot is
    // only the way out.
    final withDoor = <String, Harness Function()>{
      'no family': () => Harness(signedIn: true)..family = null,
      'the email unverified': () => Harness(signedIn: true)
        ..family = null
        ..unverified = true,
      'a failed load': () =>
          Harness(signedIn: true)
            ..familyRead = () => problem(503, 'unavailable'),
    };
    for (final MapEntry(key: state, value: harness) in withDoor.entries) {
      testWidgets('with $state, the door names the account and the foot is '
          'just Sair da conta', (tester) async {
        await harness().pump(tester, initial: '/');

        expect(find.textContaining('Você entrou como'), findsNothing);
        expect(
          find.descendant(
            of: find.widgetWithText(DoorRow, 'Sua conta'),
            matching: find.text(addressBreaks('ana@example.com')),
          ),
          findsOneWidget,
        );
        expect(find.text('Sair da conta'), findsOneWidget);
      });
    }

    testWidgets('while the family loads, with no door yet, the foot still '
        'names the account', (tester) async {
      final answer = Completer<http.Response>();
      final semantics = tester.ensureSemantics();
      final h = Harness(signedIn: true)..familyRead = () => answer.future;
      await h.pump(tester, initial: '/');

      expect(find.widgetWithText(DoorRow, 'Sua conta'), findsNothing);
      // Shown with the address's break marks, read plain (Plain Address
      // Rule).
      expect(
        find.text('Você entrou como ${addressBreaks('ana@example.com')}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Você entrou como ana@example.com'),
        findsOneWidget,
      );
      answer.complete(json(200, ownerFamily));
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets('signs out and lands on /entrar', (tester) async {
      final h = await home(tester, family: null);

      await tester.ensureVisible(find.text('Sair da conta'));
      await tester.tap(find.text('Sair da conta'));
      await tester.pumpAndSettle();

      expect(h.actions, ['DELETE /v1/session']);
      expect(find.byType(EntryScreen), findsOneWidget);
    });

    testWidgets('still lands on /entrar when the server is unreachable', (
      tester,
    ) async {
      await home(
        tester,
        family: null,
        api: (_) => throw http.ClientException('down'),
      );

      await tester.ensureVisible(find.text('Sair da conta'));
      await tester.tap(find.text('Sair da conta'));
      await tester.pumpAndSettle();

      expect(find.byType(EntryScreen), findsOneWidget);
    });

    for (final state in ['no family', 'unverified', 'failed']) {
      testWidgets('stays at the foot when $state', (tester) async {
        final h = Harness(signedIn: true)..unverified = state == 'unverified';
        if (state == 'failed') {
          h.familyRead = () => problem(503, 'unavailable');
        }
        await h.pump(tester, initial: '/');

        expect(find.text('Sair da conta'), findsOneWidget);
      });
    }
  });

  testWidgets('the home is the family home', (tester) async {
    await home(tester);

    expect(find.byType(FamilyHomeScreen), findsOneWidget);
  });

  group('the role doors', () {
    // Each door's line, path and the roles that show it.
    const doors = {
      'Curadoria': ('Fila de revisão', '/curadoria', ['curator']),
      'Pacotinhos': ('Montar e revisar', '/pacotinhos', ['curator']),
      'Moderação': ('Vídeos retidos', '/moderacao/retidos', ['moderator']),
      'Administração': (
        'Contas, equipe, vídeos e auditoria',
        '/admin',
        ['admin'],
      ),
    };

    List<String> titles(WidgetTester tester) => tester
        .widgetList<DoorRow>(find.byType(DoorRow))
        .map((d) => d.title)
        .toList();

    for (final (roles, expected) in [
      (['curator'], ['Curadoria', 'Pacotinhos']),
      (['curator', 'moderator'], ['Curadoria', 'Pacotinhos', 'Moderação']),
      (['moderator'], ['Moderação']),
      (['admin'], ['Administração']),
      (['admin', 'curator'], ['Curadoria', 'Pacotinhos', 'Administração']),
      // An admin who also moderates sees only Administração.
      (['admin', 'moderator'], ['Administração']),
      (
        ['admin', 'curator', 'moderator'],
        ['Curadoria', 'Pacotinhos', 'Administração'],
      ),
    ]) {
      for (final (what, answer, firstUse) in [
        ('no family', null, 'Tenho um convite'),
        (
          'an invitation',
          invitationsFor(['carla@example.com']),
          'Prefere começar a sua?',
        ),
        (
          'two invitations',
          invitationsFor(['carla@example.com', 'davi@example.com']),
          'Prefere começar a sua?',
        ),
      ]) {
        testWidgets('with $roles and $what, the home shows $expected below '
            'the first use and before Sua conta', (tester) async {
          await home(tester, family: null, roles: roles, api: answer);

          expect(titles(tester), [...expected, 'Sua conta']);
          expect(find.widgetWithText(DoorRow, 'Sugerir vídeo'), findsNothing);
          expect(
            tester.getTopLeft(find.text(firstUse)).dy,
            lessThan(
              tester
                  .getTopLeft(find.widgetWithText(DoorRow, expected.first))
                  .dy,
            ),
          );
        });
      }
    }

    for (final MapEntry(key: title, value: (line, path, roles))
        in doors.entries) {
      for (final family in [null]) {
        testWidgets('$title says "$line" and opens $path, with no family', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          final h = await home(tester, family: family, roles: roles);
          final door = find.widgetWithText(DoorRow, title);

          expect(
            find.descendant(of: door, matching: find.text(line)),
            findsOneWidget,
          );
          expect(find.bySemanticsLabel('$title, $line'), findsOne);
          await tester.ensureVisible(door);
          await tester.pumpAndSettle();
          await tester.tap(door);
          await tester.pumpAndSettle();

          expect(h.location(tester), path);
          semantics.dispose();
        });
      }
    }

    testWidgets('they are not in the email-to-confirm state', (tester) async {
      await home(
        tester,
        family: null,
        unverified: true,
        roles: ['admin', 'curator', 'moderator'],
      );

      for (final title in doors.keys) {
        expect(find.widgetWithText(DoorRow, title), findsNothing);
      }
    });
  });
}

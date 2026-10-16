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
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/kid_mode/kid_mode_status.dart';

import '../access/a11y_test.dart' show invitationsFor;
import '../access/harness.dart';
import '../parental/parental_api_test.dart' show deviceJson;
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
}) async {
  final h = Harness(signedIn: true, api: api)
    ..family = family
    ..unverified = unverified
    ..roles = roles;
  await h.pump(tester, initial: '/');
  return h;
}

void main() {
  group('member', () {
    testWidgets('the owner sees three doors with their counts', (tester) async {
      await home(tester);

      expect(find.text('Sua família'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(DoorRow), matching: find.byType(Text)),
        findsWidgets,
      );
      for (final title in ['Crianças', 'Responsáveis', 'Convites']) {
        expect(find.widgetWithText(DoorRow, title), findsOneWidget);
      }
      expect(find.byType(AvatarDisc), findsOneWidget);
      expect(find.text('1 de 10 crianças'), findsOneWidget);
      // Two members plus one pending invitation.
      expect(find.text('3 de 6 vagas: 2 adultos e 1 convite'), findsOneWidget);
      expect(find.text('1 convite esperando resposta'), findsOneWidget);
      final capacities = tester.widgetList<CapacityRow>(
        find.byType(CapacityRow),
      );
      expect(capacities.map((c) => (c.filled, c.total)), [(1, 10), (3, 6)]);
    });

    testWidgets('a guardian sees no Convites door', (tester) async {
      await home(tester, family: guardianFamily);

      expect(find.widgetWithText(DoorRow, 'Convites'), findsNothing);
      // Crianças, Responsáveis, Modo criança, Tempo de tela, Vídeos,
      // Sugerir vídeo and Sua conta.
      expect(find.byType(DoorRow), findsNWidgets(7));
    });

    testWidgets('each door reads its words to assistive technology', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await home(tester);

      expect(find.bySemanticsLabel('Crianças, 1 de 10 crianças'), findsOne);
      expect(
        find.bySemanticsLabel(
          'Responsáveis, 3 de 6 vagas: 2 adultos e 1 convite',
        ),
        findsOne,
      );
      expect(
        find.bySemanticsLabel('Convites, 1 convite esperando resposta'),
        findsOne,
      );
      semantics.dispose();
    });

    for (final (door, path) in [
      ('Crianças', '/familia/criancas'),
      ('Responsáveis', '/familia/responsaveis'),
      ('Convites', '/familia/convites'),
    ]) {
      testWidgets('$door opens $path', (tester) async {
        final h = await home(tester);

        await tester.tap(find.widgetWithText(DoorRow, door));
        await tester.pumpAndSettle();

        expect(h.location(tester), path);
      });
    }

    testWidgets('the owner\'s quiet foot offers Excluir família, which '
        'opens its screen', (tester) async {
      final h = await home(tester);

      expect(find.text('Sair da família'), findsNothing);
      await tester.ensureVisible(find.text('Excluir família'));
      await tester.tap(find.text('Excluir família'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/excluir');
    });

    testWidgets('the foot\'s text links start on the column edge', (
      tester,
    ) async {
      await home(tester);

      final edge = tester.getTopLeft(find.byType(Doors)).dx;
      for (final link in ['Excluir família', 'Sair da conta']) {
        expect(tester.getTopLeft(find.text(link)).dx, edge, reason: link);
      }
    });

    testWidgets('a guardian\'s foot offers Sair da família, which opens the '
        'adults', (tester) async {
      final h = await home(tester, family: guardianFamily);

      expect(find.text('Excluir família'), findsNothing);
      await tester.ensureVisible(find.text('Sair da família'));
      await tester.tap(find.text('Sair da família'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/responsaveis');
    });
  });

  group('the Modo criança door', () {
    Future<Harness> door(
      WidgetTester tester, {
      Map<String, Object?> family = ownerFamily,
      bool pinSet = false,
      int devices = 0,
      FutureOr<http.Response> Function(http.Request)? read,
    }) async {
      final h = Harness(signedIn: true)
        ..family = family
        ..pinSet = pinSet
        ..linkedDevices = [
          for (var i = 0; i < devices; i++) {...deviceJson, 'id': 'd$i'},
        ]
        ..parentalRead = read;
      await h.pump(tester, initial: '/');
      return h;
    }

    Finder kidDoor() => find.widgetWithText(DoorRow, 'Modo criança');

    List<bool> modulesIn(WidgetTester tester, Finder row) => tester
        .widgetList<StateModule>(
          find.descendant(of: row, matching: find.byType(StateModule)),
        )
        .map((m) => m.filled)
        .toList();

    for (final (role, family) in [
      ('owner', ownerFamily),
      ('guardian', guardianFamily),
    ]) {
      testWidgets('the $role sees it after the family\'s other doors, '
          'before Tempo de tela and Sua conta', (tester) async {
        await door(tester, family: family);

        final titles = tester
            .widgetList<DoorRow>(find.byType(DoorRow))
            .map((d) => d.title)
            .toList();
        expect(titles.sublist(titles.length - 5), [
          'Modo criança',
          'Tempo de tela',
          'Vídeos',
          'Sugerir vídeo',
          'Sua conta',
        ]);
      });
    }

    testWidgets('it is not in the pre-family states', (tester) async {
      await home(tester, family: null);

      expect(kidDoor(), findsNothing);
    });

    testWidgets('no PIN and no device: two hollow modules with their words', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await door(tester);

      final row = kidDoor();
      for (final words in [
        'Crie o PIN para começar',
        'Nenhum aparelho vinculado',
      ]) {
        expect(find.descendant(of: row, matching: find.text(words)), findsOne);
      }
      expect(modulesIn(tester, row), [false, false]);
      expect(
        find.bySemanticsLabel(
          'Modo criança, Crie o PIN para começar, Nenhum aparelho vinculado',
        ),
        findsOne,
      );
      semantics.dispose();
    });

    for (final (n, words) in [
      (1, '1 aparelho vinculado'),
      (2, '2 aparelhos vinculados'),
    ]) {
      testWidgets('a PIN and $n linked: both modules filled', (tester) async {
        final semantics = tester.ensureSemantics();
        await door(tester, pinSet: true, devices: n);

        final row = kidDoor();
        expect(
          find.descendant(of: row, matching: find.text('PIN criado')),
          findsOne,
        );
        expect(find.descendant(of: row, matching: find.text(words)), findsOne);
        expect(modulesIn(tester, row), [true, true]);
        expect(
          find.bySemanticsLabel('Modo criança, PIN criado, $words'),
          findsOne,
        );
        semantics.dispose();
      });
    }

    testWidgets('it opens /modo-crianca', (tester) async {
      final h = await door(tester, pinSet: true);

      await tester.ensureVisible(kidDoor());
      await tester.tap(kidDoor());
      await tester.pumpAndSettle();

      expect(h.location(tester), '/modo-crianca');
    });

    testWidgets('a failed read says so and still opens /modo-crianca', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = await door(
        tester,
        read: (req) => req.url.path.endsWith('/devices')
            ? problem(503, 'unavailable')
            : json(200, {'set': true}),
      );

      final row = kidDoor();
      expect(
        find.descendant(of: row, matching: find.text(kidModeUnknown)),
        findsOne,
      );
      expect(
        find.descendant(of: row, matching: find.text('PIN criado')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Modo criança, $kidModeUnknown'), findsOne);
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(h.location(tester), '/modo-crianca');
      semantics.dispose();
    });

    testWidgets('the other doors do not wait for the kid-mode reads', (
      tester,
    ) async {
      final answer = Completer<http.Response>();
      final h = Harness(signedIn: true)
        ..family = ownerFamily
        ..parentalRead = (_) => answer.future;
      await h.pump(tester, initial: '/');

      expect(find.widgetWithText(DoorRow, 'Crianças'), findsOne);
      expect(kidDoor(), findsOne);
      expect(find.text('PIN criado'), findsNothing);
      expect(find.text('Crie o PIN para começar'), findsNothing);

      answer.complete(json(200, {'set': true}));
      await tester.pumpAndSettle();
    });
  });

  group('the Sua conta door', () {
    Finder accountDoor() => find.widgetWithText(DoorRow, 'Sua conta');

    final states = <String, (Map<String, Object?>?, bool)>{
      'the owner': (ownerFamily, false),
      'a guardian': (guardianFamily, false),
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

    testWidgets('with a family, it closes the doors, above the quiet foot', (
      tester,
    ) async {
      await home(tester);

      expect(
        tester.getBottomLeft(accountDoor()).dy,
        lessThan(tester.getTopLeft(find.text('Excluir família')).dy),
      );
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
      await tester.pumpAndSettle();

      expect(h.actions, ['POST /v1/family']);
      expect(find.widgetWithText(DoorRow, 'Crianças'), findsOneWidget);
      expect(tester.widget<FieldLayout>(find.byType(FieldLayout)).rise, true);
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
      expect(find.byType(DoorRow), findsNWidgets(8));
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
      expect(find.byType(DoorRow), findsNWidgets(8));
    });
  });

  group('Sair da conta', () {
    // The "Sua conta" door names the account; the foot is
    // only the way out.
    final withDoor = <String, Harness Function()>{
      'the owner': () => Harness(signedIn: true)..family = ownerFamily,
      'a guardian': () => Harness(signedIn: true)..family = guardianFamily,
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
      final h = await home(tester);

      await tester.ensureVisible(find.text('Sair da conta'));
      await tester.tap(find.text('Sair da conta'));
      await tester.pumpAndSettle();

      expect(h.actions, ['DELETE /v1/session']);
      expect(find.byType(EntryScreen), findsOneWidget);
    });

    testWidgets('still lands on /entrar when the server is unreachable', (
      tester,
    ) async {
      await home(tester, api: (_) => throw http.ClientException('down'));

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

  group('the Tempo de tela door', () {
    Finder timeDoor() => find.widgetWithText(DoorRow, 'Tempo de tela');

    for (final (role, family) in [
      ('owner', ownerFamily),
      ('guardian', guardianFamily),
    ]) {
      testWidgets('the $role sees it, saying what it holds', (tester) async {
        final semantics = tester.ensureSemantics();
        await home(tester, family: family);

        expect(timeDoor(), findsOneWidget);
        expect(
          find.descendant(
            of: timeDoor(),
            matching: find.text('Limite e horário de cada criança'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            'Tempo de tela, Limite e horário de cada criança',
          ),
          findsOne,
        );
        semantics.dispose();
      });
    }

    testWidgets('it opens /familia/tempo', (tester) async {
      final h = await home(tester);

      await tester.ensureVisible(timeDoor());
      await tester.pumpAndSettle();
      await tester.tap(timeDoor());
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/tempo');
    });

    testWidgets('with no children it says so, with no chevron, and is no '
        'target', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await home(tester, family: familyWith([]));

      expect(
        find.descendant(
          of: timeDoor(),
          matching: find.text('Cadastre uma criança primeiro'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: timeDoor(),
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsNothing,
      );
      expect(
        tester.getSemantics(timeDoor()),
        isSemantics(isButton: false, hasTapAction: false),
      );
      await tester.ensureVisible(timeDoor());
      await tester.pumpAndSettle();
      await tester.tap(timeDoor(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.location(tester), '/');
      semantics.dispose();
    });

    testWidgets('it is not in the pre-family states', (tester) async {
      await home(tester, family: null);

      expect(timeDoor(), findsNothing);
    });
  });

  testWidgets('the home is the family home', (tester) async {
    await home(tester);

    expect(find.byType(FamilyHomeScreen), findsOneWidget);
  });

  group('the Vídeos door', () {
    Finder videosDoor() => find.widgetWithText(DoorRow, 'Vídeos');

    for (final (role, family) in [
      ('owner', ownerFamily),
      ('guardian', guardianFamily),
    ]) {
      testWidgets('the $role sees it after Tempo de tela and before '
          'Sugerir vídeo, saying what it holds', (tester) async {
        final semantics = tester.ensureSemantics();
        await home(tester, family: family);

        final titles = tester
            .widgetList<DoorRow>(find.byType(DoorRow))
            .map((d) => d.title)
            .toList();
        final at = titles.indexOf('Vídeos');
        expect(titles.sublist(at - 1, at + 2), [
          'Tempo de tela',
          'Vídeos',
          'Sugerir vídeo',
        ]);
        expect(
          find.bySemanticsLabel('Vídeos, O que cada criança pode assistir'),
          findsOne,
        );
        semantics.dispose();
      });
    }

    testWidgets('it opens /familia/videos', (tester) async {
      final h = await home(tester);

      await tester.ensureVisible(videosDoor());
      await tester.pumpAndSettle();
      await tester.tap(videosDoor());
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/videos');
    });

    testWidgets('with no children it says so, with no chevron, and is no '
        'target', (tester) async {
      final h = await home(tester, family: familyWith([]));

      expect(
        find.descendant(
          of: videosDoor(),
          matching: find.text('Cadastre uma criança primeiro'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<DoorRow>(videosDoor()).onTap, isNull);
      await tester.ensureVisible(videosDoor());
      await tester.pumpAndSettle();
      await tester.tap(videosDoor(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.location(tester), '/');
    });
  });

  group('the role doors', () {
    // Each door's line, path and the roles that show it.
    const doors = {
      'Sugerir vídeo': (
        'Indique um vídeo para a curadoria',
        '/sugestoes',
        <String>[],
      ),
      'Curadoria': ('Fila de revisão', '/curadoria', ['curator']),
      'Pacotinhos': ('Montar e revisar', '/pacotinhos', ['curator']),
      'Moderação': ('Vídeos retidos', '/moderacao/retidos', ['moderator']),
      'Administração': (
        'Contas, equipe, vídeos e auditoria',
        '/admin',
        ['admin'],
      ),
    };
    const roleDoors = ['Curadoria', 'Pacotinhos', 'Moderação', 'Administração'];

    List<String> titles(WidgetTester tester) => tester
        .widgetList<DoorRow>(find.byType(DoorRow))
        .map((d) => d.title)
        .toList();

    for (final (who, family) in [
      ('owner', ownerFamily),
      ('guardian', guardianFamily),
    ]) {
      testWidgets('the $who without a role sees only Sugerir vídeo, after '
          'Tempo de tela and before Sua conta', (tester) async {
        await home(tester, family: family);

        final t = titles(tester);
        expect(t.sublist(t.length - 4), [
          'Tempo de tela',
          'Vídeos',
          'Sugerir vídeo',
          'Sua conta',
        ]);
        for (final title in roleDoors) {
          expect(find.widgetWithText(DoorRow, title), findsNothing);
        }
      });
    }

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
      testWidgets('with $roles, the family shows $expected after Sugerir '
          'vídeo and before Sua conta', (tester) async {
        await home(tester, roles: roles);

        final t = titles(tester);
        expect(t.sublist(t.indexOf('Vídeos')), [
          'Vídeos',
          'Sugerir vídeo',
          ...expected,
          'Sua conta',
        ]);
      });

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
      for (final family in [ownerFamily, null]) {
        // Sugerir vídeo stays with the family's doors.
        if (family == null && title == 'Sugerir vídeo') continue;
        final where = family == null ? 'with no family' : 'in the family';
        testWidgets('$title says "$line" and opens $path, $where', (
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

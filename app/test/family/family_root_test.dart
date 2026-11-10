import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/family_root_screen.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/kid_mode/kid_mode_status.dart';

import '../access/harness.dart';
import '../parental/parental_api_test.dart' show deviceJson;
import 'family_home_test.dart' show guardianFamily;
import 'fixtures.dart';

/// `/familia`, the Família destination's root: the family's areas as
/// doors, and leaving or deleting the family at its foot.
Future<Harness> home(
  WidgetTester tester, {
  Map<String, Object?>? family = ownerFamily,
  FutureOr<http.Response> Function(http.Request)? api,
  List<String> roles = const [],
  Size size = const Size(390, 844),
}) async {
  final h = Harness(signedIn: true, api: api)
    ..family = family
    ..roles = roles;
  await h.pump(tester, initial: '/familia', size: size);
  return h;
}

List<String> titles(WidgetTester tester) => tester
    .widgetList<DoorRow>(find.byType(DoorRow))
    .map((d) => d.title)
    .toList();

void main() {
  testWidgets('/familia is the family\'s areas, titled Sua família', (
    tester,
  ) async {
    await home(tester);

    expect(find.byType(FamilyRootScreen), findsOneWidget);
    expect(find.text('Sua família'), findsOneWidget);
    expect(titles(tester), [
      'Crianças',
      'Responsáveis',
      'Convites',
      'Modo criança',
    ]);
  });

  testWidgets('a child\'s time and videos are no door of their own: they '
      'live on the child\'s page', (tester) async {
    await home(tester);

    expect(find.widgetWithText(DoorRow, 'Tempo de tela'), findsNothing);
    expect(find.widgetWithText(DoorRow, 'Vídeos'), findsNothing);
  });

  testWidgets('it holds no door the other destinations took', (tester) async {
    await home(tester, roles: ['admin', 'curator', 'moderator']);

    for (final title in [
      'Sugerir vídeo',
      'Sua conta',
      'Curadoria',
      'Pacotinhos',
      'Moderação',
      'Administração',
    ]) {
      expect(find.widgetWithText(DoorRow, title), findsNothing, reason: title);
    }
    expect(find.text('Sair da conta'), findsNothing);
  });

  testWidgets('placeholder rows while the family loads', (tester) async {
    final answer = Completer<http.Response>();
    final h = Harness(signedIn: true)..familyRead = () => answer.future;
    await h.pump(tester, initial: '/familia');

    expect(find.byKey(const Key('family-placeholder')), findsOneWidget);
    answer.complete(json(200, ownerFamily));
    await tester.pumpAndSettle();
    expect(find.byType(DoorRow), findsNWidgets(4));
  });

  testWidgets('with no family, /familia goes home to the first use', (
    tester,
  ) async {
    final h = await home(tester, family: null);

    expect(h.location(tester), '/');
    expect(find.text('Começar minha família'), findsOneWidget);
  });

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
      // Crianças, Responsáveis and Modo criança.
      expect(find.byType(DoorRow), findsNWidgets(3));
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

    testWidgets('the foot\'s text link starts on the column edge', (
      tester,
    ) async {
      await home(tester);

      final edge = tester.getTopLeft(find.byType(Doors)).dx;
      expect(tester.getTopLeft(find.text('Excluir família')).dx, edge);
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
      await h.pump(tester, initial: '/familia');
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
      testWidgets('the $role sees it last, after the family\'s other '
          'doors', (tester) async {
        await door(tester, family: family);

        expect(titles(tester).last, 'Modo criança');
      });
    }

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
      await h.pump(tester, initial: '/familia');

      expect(find.widgetWithText(DoorRow, 'Crianças'), findsOne);
      expect(kidDoor(), findsOne);
      expect(find.text('PIN criado'), findsNothing);
      expect(find.text('Crie o PIN para começar'), findsNothing);

      answer.complete(json(200, {'set': true}));
      await tester.pumpAndSettle();
    });
  });
}

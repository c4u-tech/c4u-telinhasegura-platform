import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/family/adults_screen.dart' show ownerLeaves;
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import 'fixtures.dart';

/// The suspended account.
const title = 'Sua conta está suspensa';
const onlyLine =
    'Enquanto isso, você só consegue baixar seus dados, excluir a conta ou '
    'sair.';
const familyLine =
    'A família e os aparelhos das crianças continuam funcionando.';
String appealLine(String email, [String Function(String) set = _plain]) =>
    'Para contestar, responda ao e-⁠mail que enviamos para '
    '${set(email)}.';

String _plain(String s) => s;

/// What a suspended session reaches.
const allowList = {
  'GET /v1/session',
  'DELETE /v1/session',
  'POST /v1/session/reauth',
  'POST /v1/session/refresh',
  'GET /v1/account/export',
  'DELETE /v1/account',
  'GET /v1/family',
  'POST /v1/family/owner',
  'DELETE /v1/family',
};

final guardianFamily = <String, Object?>{...ownerFamily, 'role': 'guardian'};

/// The owner alone: no other adult to hand the family to.
final aloneFamily = <String, Object?>{
  ...ownerFamily,
  'members': [(ownerFamily['members']! as List).first],
  'pending_invitations': 0,
  'invitations': <Object>[],
};

/// Every call [h] made, without its body, outside the allow-list.
List<String> outside(Harness h) => [
  for (final c in h.calls)
    if (!allowList.contains(c.split(' ').take(2).join(' '))) c,
];

Future<Harness> suspended(
  WidgetTester tester, {
  Map<String, Object?>? family = ownerFamily,
  FutureOr<http.Response> Function(http.Request)? api,
  List<String> roles = const [],
  String initial = '/',
}) async {
  final h = Harness(signedIn: true, api: api)
    ..family = family
    ..status = 'suspended'
    ..roles = roles;
  await h.pump(tester, initial: initial);
  return h;
}

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await tester.pumpAndSettle();
}

void main() {
  group('the suspended home', () {
    testWidgets('with a family: the title, the three lines, two doors and '
        'the foot; no other door', (tester) async {
      await suspended(tester, roles: ['admin', 'curator']);

      expect(find.text(title), findsOneWidget);
      expect(find.text(onlyLine), findsOneWidget);
      expect(find.text(familyLine), findsOneWidget);
      expect(
        find.text(appealLine('ana@example.com', addressBreaks)),
        findsOneWidget,
      );
      expect(find.byType(DoorRow), findsNWidgets(2));
      final data = find.widgetWithText(DoorRow, 'Seus dados');
      expect(
        find.descendant(of: data, matching: find.text('Baixar uma cópia')),
        findsOneWidget,
      );
      expect(find.widgetWithText(DoorRow, 'Excluir conta'), findsOneWidget);
      expect(find.text('Sair da conta'), findsOneWidget);
      for (final gone in [
        'Sua família',
        'Crianças',
        'Modo criança',
        'Administração',
        'Curadoria',
        'Sua conta',
        'Excluir família',
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
    });

    testWidgets('never the reason or the date: nothing of the sheet', (
      tester,
    ) async {
      await suspended(tester);

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(texts, isNot(contains('Motivo')));
      expect(texts, isNot(contains('desde')));
    });

    testWidgets('without a family, no family line', (tester) async {
      await suspended(tester, family: null);

      expect(find.text(title), findsOneWidget);
      expect(find.text(onlyLine), findsOneWidget);
      expect(find.text(familyLine), findsNothing);
      expect(find.byType(DoorRow), findsNWidgets(2));
      expect(find.text('Começar minha família'), findsNothing);
    });

    testWidgets('the appeal line reads the address plain', (tester) async {
      final semantics = tester.ensureSemantics();
      await suspended(tester);

      expect(
        find.bySemanticsLabel(appealLine('ana@example.com')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('the doors open the data and the erasure', (tester) async {
      final h = await suspended(tester);

      await tester.tap(find.widgetWithText(DoorRow, 'Seus dados'));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/conta/dados');

      await go(tester, '/');
      await tester.tap(find.widgetWithText(DoorRow, 'Excluir conta'));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/conta/excluir');
    });

    testWidgets('Sair da conta signs out', (tester) async {
      final h = await suspended(tester);

      await tester.ensureVisible(find.text('Sair da conta'));
      await tester.tap(find.text('Sair da conta'));
      await tester.pumpAndSettle();

      expect(h.calls, contains('DELETE /v1/session'));
      expect(h.location(tester), '/entrar');
    });

    testWidgets('a failed family read: the error note and Tentar de novo', (
      tester,
    ) async {
      final h = Harness(signedIn: true)
        ..status = 'suspended'
        ..familyRead = () => problem(503, 'unavailable');
      await h.pump(tester);

      expect(find.byType(ErrorNote), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(find.byType(DoorRow), findsNothing);
    });
  });

  testWidgets('a 403 account_suspended from any call takes the person to '
      'the suspended home', (tester) async {
    final h = Harness(
      signedIn: true,
      api: (req) => req.url.path == '/v1/sessions'
          ? problem(403, 'account_suspended')
          : http.Response('', 204),
    )..family = ownerFamily;
    await h.pump(tester);
    expect(find.text('Sua família'), findsOneWidget);

    h.status = 'suspended';
    await go(tester, '/conta/aparelhos');

    expect(h.location(tester), '/');
    expect(find.text(title), findsOneWidget);
    expect(find.byType(Notice), findsNothing, reason: 'the screen says it');
  });

  group('the route set', () {
    for (final path in [
      '/conta',
      '/conta/email',
      '/conta/senha',
      '/conta/aparelhos',
      '/conta/verificacao',
      '/familia/criancas',
      '/familia/convites',
      '/familia/tempo',
      '/familia/videos',
      '/modo-crianca',
      '/sugestoes',
      '/curadoria',
      '/admin',
      '/moderacao',
      '/convite?token=t',
    ]) {
      testWidgets('$path goes home', (tester) async {
        final h = await suspended(tester, roles: ['admin', 'curator']);

        await go(tester, path);

        expect(h.location(tester), '/');
        expect(outside(h), isEmpty);
      });
    }

    for (final path in ['/conta/dados', '/conta/excluir']) {
      testWidgets('$path opens, owner or not', (tester) async {
        final h = await suspended(tester, family: guardianFamily);

        await go(tester, path);

        expect(h.location(tester), path);
      });
    }

    for (final path in ['/familia/responsaveis', '/familia/excluir']) {
      testWidgets('$path opens for the owner', (tester) async {
        final h = await suspended(tester);

        await go(tester, path);

        expect(h.location(tester), path);
      });

      testWidgets('$path goes home for a guardian', (tester) async {
        final h = await suspended(tester, family: guardianFamily);

        await go(tester, path);

        expect(h.location(tester), '/');
      });

      testWidgets('$path goes home with no family', (tester) async {
        final h = await suspended(tester, family: null);

        await go(tester, path);

        expect(h.location(tester), '/');
      });
    }
  });

  group('no call outside the allow-list', () {
    for (final (name, family) in [
      ('owner', ownerFamily),
      ('guardian', guardianFamily),
      ('no family', null),
    ]) {
      testWidgets('$name: a walk through /, /conta/dados and /conta/excluir', (
        tester,
      ) async {
        final h = await suspended(tester, family: family);

        await tester.tap(find.widgetWithText(DoorRow, 'Seus dados'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Voltar'));
        await tester.pumpAndSettle();
        expect(h.location(tester), '/');
        await tester.tap(find.widgetWithText(DoorRow, 'Excluir conta'));
        await tester.pumpAndSettle();
        expect(h.location(tester), '/conta/excluir');
        await tester.tap(find.byTooltip('Voltar'));
        await tester.pumpAndSettle();

        expect(h.location(tester), '/');
        expect(h.calls, isNotEmpty);
        expect(outside(h), isEmpty);
      });
    }

    testWidgets('the owner\'s way through /familia/responsaveis', (
      tester,
    ) async {
      final h = await suspended(tester, initial: '/');

      await go(tester, '/conta/excluir');
      await tester.tap(
        find.widgetWithText(DoorRow, 'Tornar outro adulto titular'),
      );
      await tester.pumpAndSettle();
      expect(h.location(tester), '/familia/responsaveis');
      await go(tester, '/familia/excluir');

      expect(outside(h), isEmpty);
    });
  });

  group('the owner\'s restricted paths', () {
    testWidgets('/conta/excluir with another adult: the transfer door and '
        'Excluir a família', (tester) async {
      await suspended(tester);
      await go(tester, '/conta/excluir');

      expect(
        find.widgetWithText(DoorRow, 'Tornar outro adulto titular'),
        findsOneWidget,
      );
      expect(find.text('Excluir a família'), findsOneWidget);
      expect(find.text('Convidar outro adulto'), findsNothing);
    });

    testWidgets('/conta/excluir alone: only Excluir a família', (tester) async {
      final h = await suspended(tester, family: aloneFamily);
      await go(tester, '/conta/excluir');

      expect(find.byType(DoorRow), findsNothing);
      expect(find.text('Convidar outro adulto'), findsNothing);
      // The copy offers nothing the session cannot reach.
      expect(find.textContaining('convide'), findsNothing);
      expect(
        find.text(
          'Você é titular da família, e só você cuida dela. Para '
          'excluir sua conta, exclua antes a família.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Excluir a família'));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/familia/excluir');
    });

    testWidgets('/familia/responsaveis: only the transfer on each adult', (
      tester,
    ) async {
      final h = await suspended(
        tester,
        api: (req) => req.url.path == '/v1/family/owner'
            ? json(200, {...ownerFamily, 'role': 'guardian'})
            : http.Response('', 204),
      );
      await go(tester, '/familia/responsaveis');

      expect(find.text('Convidar responsável'), findsNothing);
      expect(find.text('Sair da família'), findsNothing);
      expect(find.text(ownerLeaves), findsNothing);

      final bia = addressBreaks('bia@example.com');
      await tester.tap(find.widgetWithText(DoorRow, bia));
      await tester.pumpAndSettle();
      expect(find.text('Remover'), findsNothing);
      expect(find.text('Tornar $bia titular?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Tornar titular'));
      await tester.pumpAndSettle();

      expect(h.actions, contains('POST /v1/family/owner {"account_id":"a2"}'));
      expect(outside(h), isEmpty);
    });
  });

  group('the suspended owner\'s adults', () {
    Future<void> open(WidgetTester tester, Size size, double scale) async {
      final h = Harness(signedIn: true)
        ..family = ownerFamily
        ..status = 'suspended';
      await h.pump(tester, size: size, textScale: scale);
      await go(tester, '/familia/responsaveis');
    }

    testWidgets('labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, const Size(390, 844), 1);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('at 200% text, ${size.width.toInt()} wide: no overflow, '
          'every adult reachable', (tester) async {
        await open(tester, size, 2);

        expect(tester.takeException(), isNull);
        final rows = find.byType(DoorRow);
        expect(rows, findsOneWidget, reason: 'the guardian, to transfer to');
        await tester.ensureVisible(rows.last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('reinstated, the next home load shows the normal home', (
    tester,
  ) async {
    final h = await suspended(tester);
    expect(find.text(title), findsOneWidget);

    h.status = 'active';
    await tester.tap(find.widgetWithText(DoorRow, 'Seus dados'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(find.text('Sua família'), findsOneWidget);
    expect(find.text(title), findsNothing);
  });

  testWidgets('/conta/excluir works as today for a suspended member', (
    tester,
  ) async {
    final h = await suspended(
      tester,
      family: guardianFamily,
      api: (req) => req.url.path == '/v1/session/reauth'
          ? json(200, {'csrf_token': 'c2'})
          : http.Response('', 204),
    );
    await go(tester, '/conta/excluir');

    expect(find.text('Excluir minha conta'), findsOneWidget);
    expect(outside(h), isEmpty);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/staff/challenge.dart' show ChallengeScreen;
import 'package:telinha_segura/staff/staff_root_screen.dart';

import '../access/harness.dart';
import '../curation/fixtures.dart';
import '../family/fixtures.dart';

typedef Answer = FutureOr<http.Response> Function();

/// The three reads Equipe counts with: [queue] the curator's queue,
/// [packs] the pacotinhos' first page, [held] the held videos. Each
/// answers 12, 3 and 2 waiting by default.
FutureOr<http.Response> Function(http.Request) equipeApi({
  Answer? queue,
  Answer? packs,
  Answer? held,
}) => (req) {
  final path = req.url.path;
  if (req.method != 'GET') return http.Response('', 204);
  return switch (path) {
    '/v1/curation/queue' => queue?.call() ?? twelveQueued(),
    '/v1/curation/packs' => packs?.call() ?? threeToReview(),
    '/v1/moderation/videos' => held?.call() ?? twoHeld(),
    _ => http.Response('', 204),
  };
};

http.Response twelveQueued() =>
    queuePage([for (var i = 0; i < 12; i++) queuedJson('v$i', 'Vídeo $i')]);

/// Five pacotinhos, three of them this curator may review.
http.Response threeToReview() => packPage([
  packOf('p1', 'Hora do banho', reviewable: true),
  packOf('p2', 'Bichos do mar', reviewable: true),
  packOf('p3', 'Montado por mim'),
  packOf('p4', 'Cantigas', state: 'approved', reviewable: true, round: 2),
  packOf('p5', 'Publicado', state: 'approved'),
]);

http.Response twoHeld() => heldList([
  heldOf(queuedJson('h1', 'Retido 1')),
  heldOf(queuedJson('h2', 'Retido 2')),
]);

/// `/equipe`, the Equipe destination's root, for a session holding
/// [roles].
Future<Harness> staffRoot(
  WidgetTester tester, {
  required List<String> roles,
  Map<String, Object?>? family = ownerFamily,
  FutureOr<http.Response> Function(http.Request)? api,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final h = Harness(signedIn: true, api: api ?? equipeApi())
    ..family = family
    ..roles = roles;
  await h.pump(tester, initial: '/equipe', size: size, textScale: textScale);
  return h;
}

List<String> titles(WidgetTester tester, String section) => tester
    .widgetList<DoorRow>(
      find.descendant(
        of: find.byKey(ValueKey(section)),
        matching: find.byType(DoorRow),
      ),
    )
    .map((d) => d.title)
    .toList();

/// The figure a row ends on, when it shows one.
Finder figureOf(String title) => find.descendant(
  of: find.widgetWithText(DoorRow, title),
  matching: find.byKey(const ValueKey('figure')),
);

String? figure(WidgetTester tester, String title) {
  final found = figureOf(title);
  if (found.evaluate().isEmpty) return null;
  return tester.widget<Text>(found).data;
}

const toReview = 'Para revisar';
const tools = 'Ferramentas';

void main() {
  for (final (roles, review, tooling) in [
    (['curator'], ['Revisar vídeos', 'Pacotinhos para revisar'], <String>[]),
    (['moderator'], ['Vídeos retidos'], ['Amostra de aprovações']),
    (
      ['admin'],
      ['Vídeos retidos'],
      [
        'Buscar uma conta',
        'Pessoas da equipe',
        'Registro da equipe',
        'Amostra de aprovações',
        'Pacotinhos',
        'Números da plataforma',
      ],
    ),
    (
      ['admin', 'curator'],
      ['Revisar vídeos', 'Pacotinhos para revisar', 'Vídeos retidos'],
      [
        'Buscar uma conta',
        'Pessoas da equipe',
        'Registro da equipe',
        'Amostra de aprovações',
        'Números da plataforma',
      ],
    ),
    (
      ['curator', 'moderator'],
      ['Revisar vídeos', 'Pacotinhos para revisar', 'Vídeos retidos'],
      ['Amostra de aprovações'],
    ),
    (
      ['admin', 'moderator'],
      ['Vídeos retidos'],
      [
        'Buscar uma conta',
        'Pessoas da equipe',
        'Registro da equipe',
        'Amostra de aprovações',
        'Pacotinhos',
        'Números da plataforma',
      ],
    ),
  ]) {
    testWidgets('with $roles, "Para revisar" lists $review first, then '
        '"Ferramentas" $tooling', (tester) async {
      await staffRoot(tester, roles: roles);

      expect(find.byType(StaffRootScreen), findsOneWidget);
      expect(titles(tester, toReview), review);
      expect(titles(tester, tools), tooling);
      if (tooling.isEmpty) {
        // A section with no row for the roles is not there at all.
        expect(find.text(tools), findsNothing);
        expect(find.byKey(const ValueKey(tools)), findsNothing);
      } else {
        expect(
          tester.getTopLeft(find.text(tools)).dy,
          greaterThan(
            tester.getBottomLeft(find.widgetWithText(DoorRow, review.last)).dy,
          ),
        );
      }
      for (final section in [toReview, if (tooling.isNotEmpty) tools]) {
        final title = tester.widget<Semantics>(
          find
              .ancestor(
                of: find.text(section),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(title.properties.header, isTrue, reason: section);
      }
    });
  }

  for (final (title, path, roles) in [
    ('Revisar vídeos', '/curadoria', ['curator']),
    ('Pacotinhos para revisar', '/pacotinhos', ['curator']),
    ('Vídeos retidos', '/moderacao/retidos', ['moderator']),
    ('Buscar uma conta', '/admin/contas', ['admin']),
    ('Pessoas da equipe', '/admin/equipe', ['admin']),
    ('Registro da equipe', '/admin/auditoria', ['admin']),
    ('Amostra de aprovações', '/moderacao/auditoria', ['moderator']),
    ('Pacotinhos', '/pacotinhos', ['admin']),
    ('Números da plataforma', '/admin/numeros', ['admin']),
  ]) {
    testWidgets('$title opens $path', (tester) async {
      final h = await staffRoot(tester, roles: roles);

      await tester.ensureVisible(find.widgetWithText(DoorRow, title));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DoorRow, title));
      await tester.pumpAndSettle();

      expect(h.location(tester), path);
    });
  }

  testWidgets('each row to review ends on its count, in tabular figures, '
      'and is read with it', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await staffRoot(tester, roles: ['admin', 'curator']);

    expect(figure(tester, 'Revisar vídeos'), '12');
    expect(figure(tester, 'Pacotinhos para revisar'), '3');
    expect(figure(tester, 'Vídeos retidos'), '2');
    final style = tester.widget<Text>(figureOf('Revisar vídeos')).style!;
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    final row = find.widgetWithText(DoorRow, 'Revisar vídeos');
    expect(
      tester.getCenter(figureOf('Revisar vídeos')).dx,
      greaterThan(tester.getCenter(find.text('Revisar vídeos')).dx),
    );
    expect(
      tester.getTopRight(figureOf('Revisar vídeos')).dx,
      lessThan(tester.getTopRight(row).dx),
    );
    expect(find.bySemanticsLabel('Revisar vídeos, 12'), findsOne);
    expect(find.bySemanticsLabel('Pacotinhos para revisar, 3'), findsOne);
    expect(find.bySemanticsLabel('Vídeos retidos, 2'), findsOne);
    // Counted with the calls the screens themselves make, once each.
    for (final call in [
      'GET /v1/curation/queue',
      'GET /v1/curation/packs',
      'GET /v1/moderation/videos?state=held',
    ]) {
      expect(h.actions.where((c) => c == call), hasLength(1), reason: call);
    }
    semantics.dispose();
  });

  for (final (roles, reads) in [
    (['moderator'], ['GET /v1/moderation/videos?state=held']),
    (['curator'], ['GET /v1/curation/queue', 'GET /v1/curation/packs']),
  ]) {
    testWidgets('with $roles only $reads are read', (tester) async {
      final h = await staffRoot(tester, roles: roles);

      expect(h.actions, reads);
    });
  }

  testWidgets('a queue with another page reads "50+", never a guess', (
    tester,
  ) async {
    await staffRoot(
      tester,
      roles: ['curator'],
      api: equipeApi(
        queue: () => queuePage([
          for (var i = 0; i < 50; i++) queuedJson('v$i', 'Vídeo $i'),
        ], next: 50),
      ),
    );

    expect(figure(tester, 'Revisar vídeos'), '50+');
    expect(find.bySemanticsLabel('Revisar vídeos, 50 ou mais'), findsOne);
  });

  testWidgets('pacotinhos to review that may go on past the page read as '
      'at least what the page holds', (tester) async {
    await staffRoot(
      tester,
      roles: ['curator'],
      api: equipeApi(
        packs: () => packPage([
          packOf('p1', 'Um', reviewable: true),
          packOf('p2', 'Dois', reviewable: true),
        ], hasMore: true),
      ),
    );

    expect(figure(tester, 'Pacotinhos para revisar'), '2+');
  });

  testWidgets('pacotinhos past the page that are no longer awaiting review '
      'leave the count exact', (tester) async {
    await staffRoot(
      tester,
      roles: ['curator'],
      api: equipeApi(
        packs: () => packPage([
          packOf('p1', 'Um', reviewable: true),
          packOf('p2', 'Publicado', state: 'approved'),
        ], hasMore: true),
      ),
    );

    expect(figure(tester, 'Pacotinhos para revisar'), '1');
  });

  testWidgets('with nothing to review the row reads "nada esperando" muted, '
      'no figure', (tester) async {
    await staffRoot(
      tester,
      roles: ['admin', 'curator'],
      api: equipeApi(
        queue: () => queuePage([]),
        packs: () => packPage([packOf('p1', 'Publicado', state: 'approved')]),
        held: () => heldList([]),
      ),
    );

    for (final title in [
      'Revisar vídeos',
      'Pacotinhos para revisar',
      'Vídeos retidos',
    ]) {
      expect(figure(tester, title), isNull, reason: title);
      final line = find.descendant(
        of: find.widgetWithText(DoorRow, title),
        matching: find.text('nada esperando'),
      );
      expect(line, findsOneWidget, reason: title);
      final context = tester.element(line);
      expect(
        tester.widget<Text>(line).style?.color,
        context.palette.muted,
        reason: title,
      );
      expect(find.text('0'), findsNothing);
    }
  });

  testWidgets('pacotinhos waiting only past the page show no number, '
      'not "nada esperando"', (tester) async {
    await staffRoot(
      tester,
      roles: ['curator'],
      api: equipeApi(
        packs: () => packPage([packOf('p1', 'Montado por mim')], hasMore: true),
      ),
    );

    expect(figure(tester, 'Pacotinhos para revisar'), isNull);
    expect(find.text('nada esperando'), findsNothing);
  });

  testWidgets('while the counts load, the rows stand with no number', (
    tester,
  ) async {
    final queue = Completer<http.Response>();
    final packs = Completer<http.Response>();
    final held = Completer<http.Response>();
    await staffRoot(
      tester,
      roles: ['admin', 'curator'],
      api: equipeApi(
        queue: () => queue.future,
        packs: () => packs.future,
        held: () => held.future,
      ),
    );

    expect(titles(tester, toReview), hasLength(3));
    expect(find.byKey(const ValueKey('figure')), findsNothing);
    expect(find.text('nada esperando'), findsNothing);
    queue.complete(twelveQueued());
    packs.complete(threeToReview());
    held.complete(twoHeld());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('figure')), findsNWidgets(3));
  });

  testWidgets('a count that fails to read leaves its row, with no number', (
    tester,
  ) async {
    final h = await staffRoot(
      tester,
      roles: ['admin', 'curator'],
      api: equipeApi(
        queue: () => problem(503, 'unavailable'),
        packs: () => problem(503, 'unavailable'),
        held: () => problem(503, 'unavailable'),
      ),
    );

    expect(h.location(tester), '/equipe');
    expect(titles(tester, toReview), hasLength(3));
    expect(find.byKey(const ValueKey('figure')), findsNothing);
    expect(find.text('nada esperando'), findsNothing);
  });

  testWidgets('a curator who owes the curator terms still sees Equipe; the '
      'queue asks for them when opened', (tester) async {
    final h = await staffRoot(
      tester,
      roles: ['curator'],
      api: equipeApi(
        queue: () => problem(403, 'declaration_required'),
        packs: () => problem(403, 'declaration_required'),
      ),
    );

    expect(h.location(tester), '/equipe');
    expect(figure(tester, 'Revisar vídeos'), isNull);
  });

  testWidgets('a held count the second factor guards asks nothing on '
      'Equipe: no number, no challenge', (tester) async {
    final h = await staffRoot(
      tester,
      roles: ['moderator'],
      api: equipeApi(held: () => problem(403, 'elevation_required')),
    );

    expect(h.location(tester), '/equipe');
    expect(find.byType(ChallengeScreen), findsNothing);
    expect(figure(tester, 'Vídeos retidos'), isNull);
  });

  testWidgets('a role the server no longer grants takes its rows away', (
    tester,
  ) async {
    final held = Completer<http.Response>();
    final h = await staffRoot(
      tester,
      roles: ['curator', 'moderator'],
      api: equipeApi(held: () => held.future),
    );
    expect(titles(tester, toReview), hasLength(3));

    h.roles = ['curator'];
    held.complete(problem(403, 'not_moderator'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/equipe');
    expect(titles(tester, toReview), [
      'Revisar vídeos',
      'Pacotinhos para revisar',
    ]);
    expect(find.text(tools), findsNothing);
  });

  testWidgets('coming back from a queue reads the counts again', (
    tester,
  ) async {
    var reads = 0;
    final h = await staffRoot(
      tester,
      roles: ['curator'],
      api: equipeApi(
        queue: () => switch (++reads) {
          1 => twelveQueued(),
          _ => queuePage([queuedJson('v1', 'Um')]),
        },
      ),
    );
    expect(figure(tester, 'Revisar vídeos'), '12');

    await tester.tap(find.widgetWithText(DoorRow, 'Pacotinhos para revisar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/equipe');
    expect(figure(tester, 'Revisar vídeos'), '1');
  });

  testWidgets('a session with no platform role is sent home', (tester) async {
    final h = await staffRoot(tester, roles: []);

    expect(h.location(tester), '/');
    expect(find.byType(StaffRootScreen), findsNothing);
  });

  testWidgets('with no family, the staff root still opens, with its back '
      'to the home', (tester) async {
    final h = await staffRoot(tester, roles: ['curator'], family: null);

    expect(h.location(tester), '/equipe');
    expect(titles(tester, toReview), [
      'Revisar vídeos',
      'Pacotinhos para revisar',
    ]);
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/');
  });

  testWidgets('in the shell, the staff root has no back control', (
    tester,
  ) async {
    await staffRoot(tester, roles: ['curator']);

    expect(find.byTooltip('Voltar'), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('at 200 % text on a 360 dp phone, ${dark ? 'dark' : 'light'}, '
        'every row and count holds', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = dark
          ? Brightness.dark
          : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await staffRoot(
        tester,
        roles: ['admin', 'curator'],
        size: const Size(360, 800),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(figure(tester, 'Revisar vídeos'), '12');
      final context = tester.element(find.byType(StaffRootScreen));
      expect(
        Theme.of(context).brightness,
        dark ? Brightness.dark : Brightness.light,
      );
      for (final title in [
        'Revisar vídeos',
        'Pacotinhos para revisar',
        'Vídeos retidos',
      ]) {
        final row = tester.getRect(find.widgetWithText(DoorRow, title));
        expect(row.height, greaterThanOrEqualTo(72), reason: title);
        expect(
          tester.getRect(figureOf(title)).right,
          lessThanOrEqualTo(row.right),
          reason: title,
        );
      }
    });
  }

  testWidgets('the home without a family offers one door to Equipe', (
    tester,
  ) async {
    final h = Harness(signedIn: true, api: equipeApi())
      ..family = null
      ..roles = ['admin', 'curator'];
    await h.pump(tester);

    expect(find.widgetWithText(DoorRow, 'Equipe'), findsOneWidget);
    for (final gone in ['Curadoria', 'Moderação', 'Administração']) {
      expect(find.widgetWithText(DoorRow, gone), findsNothing, reason: gone);
    }
    await tester.tap(find.widgetWithText(DoorRow, 'Equipe'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/equipe');
  });
}

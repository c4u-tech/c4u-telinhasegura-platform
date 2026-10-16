import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/admin_pack_screen.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';
import 'appoint_screen_test.dart' show tapOn;
import 'queue_screen_test.dart' show goTo;

Future<Harness> adminPacks(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? list,
  FutureOr<http.Response> Function(String id)? pack,
  FutureOr<http.Response> Function(http.Request)? remove,
  String initial = '/admin/pacotinhos',
}) async {
  final packs = packApi(list: list, pack: pack, write: remove);
  final h =
      Harness(
          signedIn: true,
          api: (req) =>
              req.url.path.contains('/packs') ? packs(req) : adminApi()(req),
        )
        ..family = ownerFamily
        ..roles = ['admin'];
  await h.pump(tester, initial: initial);
  return h;
}

List<String> writes(Harness h) =>
    h.actions.where((a) => !a.startsWith('GET')).toList();

int listReads(Harness h) => h.actions
    .where(
      (a) => a.startsWith('GET /v1/admin/packs?') || a == 'GET /v1/admin/packs',
    )
    .length;

Finder get removeForGood => find.widgetWithText(QuietAction, 'Remover de vez');

void main() {
  group('the admin door', () {
    testWidgets('"Pacotinhos" follows "Vídeos retidos" with its count and '
        'opens the list', (tester) async {
      final h = await adminPacks(
        tester,
        initial: '/admin',
        list: (_) =>
            packPage([packOf('p1', 'Hora do banho'), packOf('p2', 'Bichos')]),
      );

      expect(find.widgetWithText(DoorRow, 'Pacotinhos'), findsOneWidget);
      expect(find.text('2 pacotinhos'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Vídeos retidos')).dy,
        lessThan(tester.getTopLeft(find.text('Pacotinhos')).dy),
      );
      await tapOn(tester, find.text('Pacotinhos'));
      expect(h.location(tester), '/admin/pacotinhos');
    });

    testWidgets('a first page with more reads "Mais de N pacotinhos"; one '
        'reads "1 pacotinho"', (tester) async {
      var more = true;
      await adminPacks(
        tester,
        initial: '/admin',
        list: (_) => more
            ? packPage([packOf('p1', 'A'), packOf('p2', 'B')], hasMore: true)
            : packPage([packOf('p1', 'A')]),
      );
      expect(find.text('Mais de 2 pacotinhos'), findsOneWidget);

      more = false;
      goTo(tester, '/admin/equipe');
      await tester.pumpAndSettle();
      goTo(tester, '/admin');
      await tester.pumpAndSettle();
      expect(find.text('1 pacotinho'), findsOneWidget);
    });
  });

  group('the list', () {
    testWidgets('lists the pacotinhos as doors in words, never "para você '
        'revisar"', (tester) async {
      final h = await adminPacks(
        tester,
        list: (_) => packPage([
          packOf('p1', 'Hora do banho', state: 'approved'),
          packOf('p2', 'Bichos', state: 'held'),
        ]),
      );

      expect(find.text('Pacotinhos'), findsWidgets);
      expect(find.byType(DoorRow), findsNWidgets(2));
      expect(find.text('Publicado'), findsOneWidget);
      expect(find.text('Recusado'), findsOneWidget);
      expect(find.textContaining('para você'), findsNothing);

      await tapOn(tester, find.text('Hora do banho'));
      expect(h.location(tester), '/admin/pacotinhos/p1');
    });

    testWidgets('"Ver mais" appends the next page', (tester) async {
      final h = await adminPacks(
        tester,
        list: (req) => req.url.queryParameters['offset'] == '1'
            ? packPage([packOf('p2', 'Bichos')])
            : packPage([packOf('p1', 'Hora do banho')], hasMore: true),
      );

      await tapOn(tester, find.text('Ver mais'));

      expect(h.actions, contains('GET /v1/admin/packs?offset=1'));
      expect(find.byType(DoorRow), findsNWidgets(2));
    });

    testWidgets('empty, it says so', (tester) async {
      await adminPacks(tester);

      expect(find.text('Nenhum pacotinho ainda.'), findsOneWidget);
    });
  });

  group('one pacotinho', () {
    Future<Harness> onePack(
      WidgetTester tester, {
      Map<String, Object?>? pack,
      FutureOr<http.Response> Function(http.Request)? remove,
    }) => adminPacks(
      tester,
      initial: '/admin/pacotinhos/p1',
      pack: (_) => json(
        200,
        pack ??
            packOf(
              'p1',
              'Hora do banho',
              state: 'approved',
              composer: 'pedagogo',
              provenance: {
                'approvals': {'mae-pai': 1, 'psicologo': 1},
                'last_reviewed_at': '2026-10-05T12:00:00Z',
              },
            ),
      ),
      remove: remove ?? (_) => http.Response('', 204),
    );

    testWidgets('shows the state, the composer, the approvals by role and '
        'the videos as read lines', (tester) async {
      await onePack(tester);

      expect(find.text('Hora do banho'), findsOneWidget);
      expect(find.text(nb('Publicado · Montado por Pedagogo(a)')), findsOne);
      // The world's one provenance grammar (DESIGN provenance-line).
      expect(
        find.textContaining(
          'Revisado por 1\u00A0mãe ou pai e 1\u00A0psicólogo(a)',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('última revisão'), findsOneWidget);
      expect(find.text('1. Galinha Pintadinha'), findsOneWidget);
      expect(find.text('3. Pato Pateta'), findsOneWidget);
      expect(find.byType(DoorRow), findsNothing, reason: 'read, not doors');
      expect(removeForGood, findsOneWidget);
    });

    testWidgets('a removed pacotinho offers no removal', (tester) async {
      await onePack(
        tester,
        pack: packOf('p1', 'Hora do banho', state: 'removed'),
      );

      expect(find.text(nb('Removido · Montado por Mãe ou pai')), findsOne);
      expect(removeForGood, findsNothing);
    });

    testWidgets('"Remover de vez" is confirmed full screen, then removed '
        'once, back to the list with a notice', (tester) async {
      final h = await onePack(tester);

      await tapOn(tester, removeForGood);
      final confirm = tester.widget<DestructiveConfirmation>(
        find.byType(DestructiveConfirmation),
      );
      expect(confirm.title, 'Remover “Hora do banho” de vez?');
      expect(
        confirm.body.join(' '),
        'Nenhuma criança vai receber este pacotinho. Não dá para desfazer.',
      );
      expect(writes(h), isEmpty);

      await tapOn(
        tester,
        find.descendant(
          of: find.byType(DestructiveConfirmation),
          matching: find.widgetWithText(FilledButton, 'Remover de vez'),
        ),
      );

      expect(writes(h), ['POST /v1/admin/packs/p1/remove']);
      expect(h.location(tester), '/admin/pacotinhos');
      expect(
        find.widgetWithText(Notice, packRemoved('Hora do banho')),
        findsOneWidget,
      );
    });

    testWidgets('cancelling removes nothing', (tester) async {
      final h = await onePack(tester);

      await tapOn(tester, removeForGood);
      await tapOn(tester, find.text('Cancelar'));

      expect(writes(h), isEmpty);
      expect(h.location(tester), '/admin/pacotinhos/p1');
    });

    testWidgets('state_conflict goes back to the list, read again, saying '
        'it was already removed', (tester) async {
      final h = await onePack(
        tester,
        remove: (_) => problem(409, 'state_conflict'),
      );

      await tapOn(tester, removeForGood);
      await tapOn(tester, find.widgetWithText(FilledButton, 'Remover de vez'));

      expect(h.location(tester), '/admin/pacotinhos');
      expect(find.widgetWithText(Notice, packAlreadyRemoved), findsOneWidget);
      expect(listReads(h), 1);
    });

    testWidgets('reauth_required asks to confirm it is you, then retries '
        'once', (tester) async {
      var confirmed = false;
      final packs = packApi(
        pack: (id) => json(200, packOf(id, 'Hora do banho')),
        write: (_) => confirmed
            ? http.Response('', 204)
            : problem(403, 'reauth_required'),
      );
      final h =
          Harness(
              signedIn: true,
              api: (req) {
                if (req.url.path == '/v1/session/reauth') {
                  confirmed = true;
                  return http.Response('', 204);
                }
                return packs(req);
              },
            )
            ..family = ownerFamily
            ..roles = ['admin'];
      await h.pump(tester, initial: '/admin/pacotinhos/p1');

      await tapOn(tester, removeForGood);
      await tapOn(tester, find.widgetWithText(FilledButton, 'Remover de vez'));
      expect(find.byType(ReauthPrompt), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'uma senha longa');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(writes(h).map((a) => a.split(' {').first), [
        'POST /v1/admin/packs/p1/remove',
        'POST /v1/session/reauth',
        'POST /v1/admin/packs/p1/remove',
      ]);
      expect(h.location(tester), '/admin/pacotinhos');
    });

    testWidgets('not_found on the read goes back to the list', (tester) async {
      final h = await adminPacks(
        tester,
        initial: '/admin/pacotinhos/p1',
        pack: (_) => problem(404, 'not_found'),
      );

      expect(h.location(tester), '/admin/pacotinhos');
      expect(find.widgetWithText(Notice, packGone), findsOneWidget);
    });
  });
}

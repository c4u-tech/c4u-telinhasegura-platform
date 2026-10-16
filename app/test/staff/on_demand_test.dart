import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../account/mfa_fixtures.dart';
import '../curation/appoint_screen_test.dart' as appoint;
import '../curation/fixtures.dart';
import '../curation/held_videos_screen_test.dart' show refused;
import '../family/fixtures.dart';
import 'account_search_screen_test.dart' as search;

const challengeTitle = 'Código do app autenticador';
const enrollTitle = 'Conecte o app autenticador';
const why = 'Saiu da equipe.';

/// Ana, an admin and moderator whose session the status calls elevated,
/// so the gate opens; the staff and pacotinho routes answer as their
/// fixtures do ([answer] first, when given), except that each request
/// [refuses] picks is answered [code] the first time it is sent.
Future<Harness> refusing(
  WidgetTester tester, {
  required String initial,
  required String code,
  required bool Function(http.Request req) refuses,
  FutureOr<http.Response>? Function(http.Request req)? answer,
}) async {
  final seen = <String>{};
  final h =
      Harness(
          signedIn: true,
          api: mfaApi(
            status: () => json(
              200,
              mfaStatusJson(
                elevatedUntil: DateTime.now().add(const Duration(minutes: 30)),
              ),
            ),
            other: (req) {
              if (refuses(req) && seen.add('${req.method} ${req.url}')) {
                return problem(403, code);
              }
              if (answer?.call(req) case final a?) return a;
              return req.url.path.contains('packs')
                  ? packApi()(req)
                  : adminApi(held: () => heldList([refused]))(req);
            },
          ),
        )
        ..family = ownerFamily
        ..roles = ['admin', 'moderator'];
  await h.pump(tester, initial: initial);
  return h;
}

bool Function(http.Request) get(String path) =>
    (req) => req.method == 'GET' && req.url.path == path;

bool Function(http.Request) post(String path) =>
    (req) => req.method == 'POST' && req.url.path == path;

List<String> sent(Harness h, String prefix) => [
  for (final c in h.actions)
    if (c.startsWith(prefix)) c,
];

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> pass(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).last, '123456');
  await tapOn(tester, find.text('Confirmar').last);
}

/// Through the enrollment's three steps to its end.
Future<void> enroll(WidgetTester tester) async {
  await tapOn(tester, find.text('Já adicionei'));
  await tester.enterText(find.byType(TextField).last, '123456');
  await tapOn(tester, find.text('Confirmar').last);
  await tapOn(tester, find.text('Guardei os códigos em um lugar seguro'));
  await tapOn(tester, find.text('Continuar').last);
}

Finder confirming(String label) => find.descendant(
  of: find.byType(DestructiveConfirmation),
  matching: find.widgetWithText(FilledButton, label),
);

Future<void> confirmWith(WidgetTester tester, String label) async {
  await tester.enterText(find.widgetWithText(TextField, 'Motivo'), why);
  await tester.pump();
  await tapOn(tester, confirming(label));
}

void main() {
  group('a staff read', () {
    for (final (initial, path, shown) in [
      ('/admin/equipe', '/v1/admin/staff', 'Nomear alguém'),
      ('/admin/equipe/a2', '/v1/admin/staff', 'Tirar da curadoria'),
      ('/moderacao/retidos', '/v1/moderation/videos', 'Vídeos retidos'),
      ('/moderacao/retidos/v1', '/v1/moderation/videos', 'Remover de vez'),
      ('/admin/pacotinhos', '/v1/admin/packs', 'Nenhum pacotinho ainda.'),
      ('/admin/pacotinhos/p1', '/v1/admin/packs/p1', 'Remover de vez'),
      ('/admin', '/v1/admin/metrics', 'Contas'),
      ('/admin/auditoria', '/v1/admin/audit', 'Nenhuma ação da equipe ainda.'),
    ]) {
      testWidgets('$initial: elevation_required shows the challenge, then '
          'reads again', (tester) async {
        final h = await refusing(
          tester,
          initial: initial,
          code: 'elevation_required',
          refuses: get(path),
        );

        expect(find.text(challengeTitle), findsOneWidget);
        expect(sent(h, 'GET $path'), hasLength(1));
        await pass(tester);

        expect(find.text(challengeTitle), findsNothing);
        expect(sent(h, 'GET $path'), hasLength(2));
        expect(h.location(tester), initial);
        expect(find.text(shown), findsWidgets);
        expect(find.byType(ErrorNote), findsNothing);
        expect(find.byType(FamilyPlaceholder), findsNothing);
      });
    }

    testWidgets('a cancelled challenge goes home', (tester) async {
      final h = await refusing(
        tester,
        initial: '/admin/equipe',
        code: 'elevation_required',
        refuses: get('/v1/admin/staff'),
      );

      await tester.tap(find.byTooltip('Voltar').last);
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
      expect(sent(h, 'GET /v1/admin/staff'), hasLength(1));
    });

    testWidgets('mfa_enrollment_required runs the enrollment, then reads '
        'again', (tester) async {
      final h = await refusing(
        tester,
        initial: '/admin/equipe',
        code: 'mfa_enrollment_required',
        refuses: get('/v1/admin/staff'),
      );

      expect(find.text(enrollTitle), findsOneWidget);
      await enroll(tester);

      expect(find.text(enrollTitle), findsNothing);
      expect(sent(h, 'GET /v1/admin/staff'), hasLength(2));
      expect(h.location(tester), '/admin/equipe');
      expect(find.text('Nomear alguém'), findsOneWidget);
    });

    testWidgets('the Administração counts refused together ask once, then '
        'each is read again', (tester) async {
      final h = await refusing(
        tester,
        initial: '/admin',
        code: 'elevation_required',
        refuses: (req) => req.method == 'GET',
      );

      expect(find.text(challengeTitle), findsOneWidget);
      await pass(tester);

      expect(sent(h, 'POST /v1/staff/mfa/challenge'), hasLength(1));
      expect(sent(h, 'GET /v1/admin/staff'), hasLength(2));
      expect(sent(h, 'GET /v1/moderation/videos'), hasLength(2));
      expect(sent(h, 'GET /v1/admin/packs'), hasLength(2));
      expect(sent(h, 'GET /v1/admin/metrics'), hasLength(2));
      expect(find.text('2 pessoas'), findsOneWidget);
    });

    testWidgets('"Ver mais" refused asks, then reads the page again', (
      tester,
    ) async {
      final h = await refusing(
        tester,
        initial: '/admin/pacotinhos',
        code: 'elevation_required',
        refuses: (req) =>
            req.url.path == '/v1/admin/packs' &&
            req.url.queryParameters['offset'] == '1',
        answer: (req) => req.url.path == '/v1/admin/packs'
            ? req.url.queryParameters['offset'] == '1'
                  ? packPage([packOf('p2', 'Bichos')])
                  : packPage([packOf('p1', 'Hora do banho')], hasMore: true)
            : null,
      );

      await tapOn(tester, find.text('Ver mais'));
      expect(find.text(challengeTitle), findsOneWidget);
      await pass(tester);

      expect(sent(h, 'GET /v1/admin/packs?offset=1'), hasLength(2));
      expect(find.byType(DoorRow), findsNWidgets(2));
    });
  });

  group('a staff write', () {
    testWidgets('elevation_required asks, then the revoke runs once more '
        'with the same Motivo', (tester) async {
      const revoke = '/v1/admin/staff/a2/roles/curator/revoke';
      final h = await refusing(
        tester,
        initial: '/admin/equipe/a2',
        code: 'elevation_required',
        refuses: post(revoke),
      );

      await tapOn(
        tester,
        find.widgetWithText(QuietAction, 'Tirar da curadoria'),
      );
      await confirmWith(tester, 'Tirar da curadoria');
      expect(find.text(challengeTitle), findsOneWidget);
      await pass(tester);

      expect(sent(h, 'POST $revoke'), [
        'POST $revoke {"reason":"$why"}',
        'POST $revoke {"reason":"$why"}',
      ]);
      expect(find.text(challengeTitle), findsNothing);
      expect(find.byType(ErrorNote), findsNothing);
    });

    testWidgets('a cancelled challenge leaves the screen as it was, with no '
        'message', (tester) async {
      const revoke = '/v1/admin/staff/a2/roles/curator/revoke';
      final h = await refusing(
        tester,
        initial: '/admin/equipe/a2',
        code: 'elevation_required',
        refuses: post(revoke),
      );

      await tapOn(
        tester,
        find.widgetWithText(QuietAction, 'Tirar da curadoria'),
      );
      await confirmWith(tester, 'Tirar da curadoria');
      await tester.tap(find.byTooltip('Voltar').last);
      await tester.pumpAndSettle();

      expect(h.location(tester), '/admin/equipe/a2');
      expect(sent(h, 'POST $revoke'), hasLength(1));
      expect(find.text('Tirar da curadoria'), findsOneWidget);
      expect(find.byType(ErrorNote), findsNothing);
    });

    testWidgets('mfa_enrollment_required runs the enrollment, then the '
        'appointment runs once more with every input', (tester) async {
      final h = await refusing(
        tester,
        initial: '/admin/equipe/nova',
        code: 'mfa_enrollment_required',
        refuses: post('/v1/admin/staff'),
      );

      await appoint.fill(tester, papel: 'Moderação');
      await tapOn(tester, appoint.proceed);
      await confirmWith(tester, 'Nomear');
      expect(find.text(enrollTitle), findsOneWidget);
      await enroll(tester);

      final grants = sent(h, 'POST /v1/admin/staff');
      expect(grants, hasLength(2));
      expect(grants.toSet(), hasLength(1));
      expect(grants.first, contains('"reason":"$why"'));
      expect(find.text('Voltar para a equipe'), findsOneWidget);
    });

    testWidgets('reopening a held video asks too, then runs once more', (
      tester,
    ) async {
      const reopen = '/v1/moderation/videos/v1/reopen';
      final h = await refusing(
        tester,
        initial: '/moderacao/retidos/v1',
        code: 'elevation_required',
        refuses: post(reopen),
      );

      await tapOn(
        tester,
        find.widgetWithText(FilledButton, 'Reabrir para revisão'),
      );
      await confirmWith(tester, 'Reabrir para revisão');
      await pass(tester);

      expect(sent(h, 'POST $reopen'), [
        'POST $reopen {"reason":"$why"}',
        'POST $reopen {"reason":"$why"}',
      ]);
      expect(h.location(tester), '/moderacao/retidos');
    });

    testWidgets('removing a held video takes the challenge and the '
        're-authentication, each once, in the server\'s order', (tester) async {
      const remove = '/v1/moderation/videos/v1/remove';
      var calls = 0;
      final h = await refusing(
        tester,
        initial: '/moderacao/retidos/v1',
        code: 'elevation_required',
        refuses: post(remove),
        answer: (req) => switch (req.url.path) {
          '/v1/session/reauth' => http.Response('', 204),
          remove when calls++ == 0 => problem(403, 'reauth_required'),
          _ => null,
        },
      );

      await tapOn(tester, find.widgetWithText(QuietAction, 'Remover de vez'));
      await confirmWith(tester, 'Remover de vez');
      await pass(tester);
      await tester.enterText(find.byType(TextField).last, 'uma senha longa');
      await tapOn(tester, find.text('Confirmar').last);

      expect(sent(h, 'POST $remove'), hasLength(3));
      expect(sent(h, 'POST $remove').toSet(), {
        'POST $remove {"reason":"$why"}',
      });
      expect(h.location(tester), '/moderacao/retidos');
    });

    testWidgets('an account lookup asks, then runs once more with the same '
        'reason, and opens the sheet', (tester) async {
      const lookup = '/v1/admin/accounts/lookup';
      final h = await refusing(
        tester,
        initial: '/admin/contas',
        code: 'elevation_required',
        refuses: post(lookup),
      );

      await search.fill(tester);
      await search.press(tester);
      expect(find.text(challengeTitle), findsOneWidget);
      await pass(tester);

      expect(sent(h, 'POST $lookup'), hasLength(2));
      expect(sent(h, 'POST $lookup').toSet(), hasLength(1));
      expect(h.location(tester), '/admin/contas/a2');
    });

    for (final (action, path) in [
      ('Enviar redefinição de senha', '/v1/admin/accounts/a2/password-reset'),
      ('Desvincular', '/v1/admin/accounts/a2/devices/d1/unlink'),
      ('Encerrar todas as sessões', '/v1/admin/accounts/a2/sessions/revoke'),
    ]) {
      testWidgets('"$action" on an account asks, then runs once more with '
          'the same Motivo', (tester) async {
        final h = await refusing(
          tester,
          initial: '/admin/contas',
          code: 'elevation_required',
          refuses: post(path),
        );

        await search.fill(tester);
        await search.press(tester);
        await tapOn(tester, find.widgetWithText(QuietAction, action));
        await confirmWith(tester, action);
        expect(find.text(challengeTitle), findsOneWidget);
        await pass(tester);

        expect(sent(h, 'POST $path'), [
          'POST $path {"reason":"$why"}',
          'POST $path {"reason":"$why"}',
        ]);
        expect(find.text(challengeTitle), findsNothing);
        expect(find.byType(ErrorNote), findsNothing);
        expect(find.byType(Notice), findsOneWidget);
        expect(h.location(tester), '/admin/contas/a2');
      });
    }

    testWidgets('an account action whose challenge is cancelled changes '
        'nothing', (tester) async {
      const path = '/v1/admin/accounts/a2/sessions/revoke';
      final h = await refusing(
        tester,
        initial: '/admin/contas',
        code: 'elevation_required',
        refuses: post(path),
      );

      await search.fill(tester);
      await search.press(tester);
      await tapOn(
        tester,
        find.widgetWithText(QuietAction, 'Encerrar todas as sessões'),
      );
      await confirmWith(tester, 'Encerrar todas as sessões');
      await tester.tap(find.byTooltip('Voltar').last);
      await tester.pumpAndSettle();

      expect(h.location(tester), '/admin/contas/a2');
      expect(sent(h, 'POST $path'), hasLength(1));
      expect(find.byType(ErrorNote), findsNothing);
      expect(find.byType(Notice), findsNothing);
      expect(find.text('Encerrar todas as sessões'), findsOneWidget);
    });

    testWidgets('removing a pacotinho asks, then runs once more', (
      tester,
    ) async {
      const remove = '/v1/admin/packs/p1/remove';
      final h = await refusing(
        tester,
        initial: '/admin/pacotinhos/p1',
        code: 'elevation_required',
        refuses: post(remove),
      );

      await tapOn(tester, find.widgetWithText(QuietAction, 'Remover de vez'));
      await tapOn(tester, confirming('Remover de vez'));
      await pass(tester);

      expect(sent(h, 'POST $remove'), hasLength(2));
      expect(h.location(tester), '/admin/pacotinhos');
    });
  });
}

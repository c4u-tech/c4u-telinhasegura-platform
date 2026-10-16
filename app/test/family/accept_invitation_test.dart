import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/family/accept_invitation_screen.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/family_model.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import 'fixtures.dart';

import 'package:telinha_segura/design/address.dart';

import '../design/pump.dart' show findAddress;

const preview = {
  'inviter_email': 'bia@example.com',
  'invited_email': 'ana@example.com',
  'expires_at': '2026-10-10T12:00:00Z',
};

/// Ana, invited into bia's family, as the API answers her joining.
final joinedFamily = <String, Object?>{
  ...ownerFamily,
  'role': 'guardian',
  'invitations': null,
};

const lookupCall = 'POST /v1/invitations/lookup {"token":"T"}';
const acceptCall = 'POST /v1/invitations/accept {"token":"T"}';

/// `/convite` signed in, over an API whose lookup answers [lookup] and
/// whose accept answers [accept] (the preview and the joined family by
/// default). The account has no family until it joins.
Future<Harness> opening(
  WidgetTester tester, {
  String path = '/convite?token=T',
  FutureOr<http.Response> Function()? lookup,
  FutureOr<http.Response> Function()? accept,
  bool unverified = false,
}) async {
  late final Harness h;
  h =
      Harness(
          signedIn: true,
          api: (req) {
            if (req.url.path == '/v1/invitations/lookup') {
              return (lookup ?? () => json(200, preview))();
            }
            if (req.url.path == '/v1/invitations/accept') {
              if (accept != null) return accept();
              h.family = joinedFamily;
              return json(200, joinedFamily);
            }
            return http.Response('', 204);
          },
        )
        ..family = null
        ..unverified = unverified;
  await h.pump(tester, initial: path);
  return h;
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String copyOf(String code) => Copy.forError(ApiError(status: 400, code: code));

Finder get join => find.widgetWithText(PrimaryButton, 'Entrar na família');

void main() {
  group('lookup', () {
    testWidgets('looks the invitation up once and shows who invited and '
        'whom, with Entrar na família', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await opening(tester);

      expect(h.actions, [lookupCall]);
      expect(find.text('Convite'), findsOneWidget);
      // Both addresses shown with their break marks, read plain (Plain
      // Address Rule).
      expect(
        find.text(
          '${addressBreaks('bia@example.com')} convidou você para a família.',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('bia@example.com convidou você para a família.'),
        findsOneWidget,
      );
      expect(findAddress('ana@example.com'), findsOneWidget);
      expect(find.bySemanticsLabel('ana@example.com'), findsOneWidget);
      expect(join, findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a new token in the URL is looked up again', (tester) async {
      final h = await opening(tester);

      GoRouter.of(tester.element(find.byType(AcceptInvitationScreen)))
          .go('/convite?token=U');
      await tester.pumpAndSettle();

      expect(h.actions, [
        lookupCall,
        'POST /v1/invitations/lookup {"token":"U"}',
      ]);
      expect(join, findsOneWidget);
    });

    testWidgets('a just-linked account routed here does not rise later on '
        'the home', (tester) async {
      final h = Harness(signedIn: true, api: (_) => json(200, preview))
        ..family = null;
      h.services.justLinked = true;
      await h.pump(tester, initial: '/convite?token=T');

      expect(h.services.justLinked, isFalse);
      GoRouter.of(tester.element(find.byType(AcceptInvitationScreen))).go('/');
      await tester.pumpAndSettle();
      expect(tester.widget<FieldLayout>(find.byType(FieldLayout)).rise, false);
    });

    testWidgets('placeholder rows while it looks, not a spinner', (
      tester,
    ) async {
      final answer = Completer<http.Response>();
      final h = Harness(signedIn: true, api: (_) => answer.future)
        ..family = null;
      await h.pump(tester, initial: '/convite?token=T');

      expect(find.byType(FamilyPlaceholder), findsOneWidget);
      expect(join, findsNothing);
      answer.complete(json(200, preview));
      await tester.pumpAndSettle();
      expect(join, findsOneWidget);
    });

    testWidgets('a missing token is an invalid invitation, asked nothing', (
      tester,
    ) async {
      final h = await opening(tester, path: '/convite');

      expect(h.actions, isEmpty);
      expect(find.text(Copy.invitationGone), findsOneWidget);
      expect(join, findsNothing);
    });

    testWidgets('a dropped connection offers Tentar de novo, which looks '
        'again', (tester) async {
      var down = true;
      final h = await opening(
        tester,
        lookup: () =>
            down ? throw http.ClientException('down') : json(200, preview),
      );

      expect(find.text(Copy.genericRetry), findsOneWidget);
      expect(join, findsNothing);
      down = false;
      await tapOn(tester, find.text('Tentar de novo'));

      expect(h.actions, [lookupCall, lookupCall]);
      expect(join, findsOneWidget);
    });

    testWidgets('a 5xx is retryable too', (tester) async {
      await opening(tester, lookup: () => problem(503, 'unavailable'));

      expect(find.text(Copy.genericRetry), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
    });

    testWidgets('rate_limited counts down before looking again', (
      tester,
    ) async {
      await opening(
        tester,
        lookup: () =>
            problem(429, 'rate_limited', headers: {'retry-after': '5'}),
      );

      expect(find.textContaining('5 s'), findsOneWidget);
      final retry = find.widgetWithText(PrimaryButton, 'Tentar de novo');
      expect(tester.widget<PrimaryButton>(retry).onPressed, isNull);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.widget<PrimaryButton>(retry).onPressed, isNotNull);
    });
  });

  group('accept', () {
    testWidgets('Entrar na família accepts, then the family home greets '
        'with the rise', (tester) async {
      final h = await opening(tester);

      await tapOn(tester, join);

      expect(h.actions, [lookupCall, acceptCall]);
      expect(h.location(tester), '/');
      expect(find.widgetWithText(DoorRow, 'Crianças'), findsOneWidget);
      expect(tester.widget<FieldLayout>(find.byType(FieldLayout)).rise, true);
      final state = h.services.familyModel.state as FamilyReady;
      expect(state.family.role, FamilyRole.guardian);
    });

    testWidgets('pending, the button shows progress and waits; a dropped '
        'connection says so and keeps the invitation', (tester) async {
      final answer = Completer<http.Response>();
      final h = await opening(tester, accept: () => answer.future);

      await tester.ensureVisible(join);
      await tester.tap(join);
      await tester.pump();
      final busy = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(busy.busy, isTrue);

      answer.completeError(http.ClientException('down'));
      await tester.pumpAndSettle();

      expect(h.actions, [lookupCall, acceptCall]);
      expect(h.location(tester), '/convite?token=T');
      expect(find.text(Copy.genericRetry), findsOneWidget);
      expect(tester.widget<PrimaryButton>(join).onPressed, isNotNull);
    });
  });

  group('problems', () {
    final problems = <String, (int, String, String)>{
      'invalid_token': (404, Copy.invitationGone, 'Ir para o início'),
      'invitation_email_mismatch': (
        403,
        copyOf('invitation_email_mismatch'),
        'Sair e entrar com outro e-\u2060mail',
      ),
      'already_in_family': (
        409,
        copyOf('already_in_family'),
        'Ir para sua família',
      ),
      'limit_reached': (409, Copy.invitationFamilyFull, 'Ir para o início'),
    };

    for (final MapEntry(key: code, value: (status, words, action))
        in problems.entries) {
      for (final step in ['lookup', 'accept']) {
        testWidgets('$code on $step says so, offers $action and no way to '
            'join', (tester) async {
          await opening(
            tester,
            lookup: step == 'lookup' ? () => problem(status, code) : null,
            accept: step == 'accept' ? () => problem(status, code) : null,
          );
          if (step == 'accept') await tapOn(tester, join);

          expect(find.text(words), findsOneWidget);
          expect(find.byType(ErrorNote), findsOneWidget);
          expect(find.widgetWithText(QuietAction, action), findsOneWidget);
          expect(
            tester.getTopLeft(find.text(action)).dx,
            tester.getTopLeft(find.byType(ErrorNote)).dx,
          );
          expect(join, findsNothing);
        });
      }
    }

    testWidgets('an invalid token reveals nothing beyond the generic copy', (
      tester,
    ) async {
      await opening(tester, lookup: () => problem(404, 'invalid_token'));

      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('convidou'), findsNothing);
    });

    testWidgets('the invitee words a full family as the family\'s, not '
        'theirs', (tester) async {
      expect(Copy.invitationFamilyFull, contains('completa'));
      expect(Copy.invitationGone, contains('expirou'));
      expect(Copy.invitationGone, contains('já foi usado'));
      expect(Copy.invitationGone, contains('titular'));
    });

    testWidgets('already_in_family links to the family home', (tester) async {
      final h = await opening(
        tester,
        lookup: () => problem(409, 'already_in_family'),
      );
      h.family = ownerFamily;

      await tapOn(tester, find.text('Ir para sua família'));

      expect(h.location(tester), '/');
    });

    testWidgets('invitation_email_mismatch signs out, keeping the token in '
        'memory, and lands on /entrar', (tester) async {
      final h = await opening(
        tester,
        lookup: () => problem(403, 'invitation_email_mismatch'),
      );
      h.signedIn = false;

      await tapOn(tester, find.text('Sair e entrar com outro e-\u2060mail'));

      expect(h.actions.last, 'DELETE /v1/session');
      expect(h.location(tester), '/entrar');
      expect(h.services.heldInvitation, 'T');
    });

    for (final step in ['lookup', 'accept']) {
      testWidgets('email_unverified on $step shows the verify prompt at /', (
        tester,
      ) async {
        final h = await opening(
          tester,
          lookup: step == 'lookup'
              ? () => problem(403, 'email_unverified')
              : null,
          accept: step == 'accept'
              ? () => problem(403, 'email_unverified')
              : null,
          unverified: true,
        );
        if (step == 'accept') await tapOn(tester, join);

        expect(h.location(tester), '/');
        expect(find.text('Reenviar e-\u2060mail'), findsOneWidget);
      });
    }
  });

  testWidgets('back returns to the home', (tester) async {
    final h = await opening(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/');
    expect(find.byType(AcceptInvitationScreen), findsNothing);
  });
}

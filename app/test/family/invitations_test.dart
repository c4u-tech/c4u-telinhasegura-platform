import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/invitations_screen.dart';

import '../access/harness.dart';
import 'fixtures.dart';
import '../design/pump.dart' show findAddress;

import 'package:telinha_segura/design/address.dart';

/// [days] calendar days from today, at noon, as the wire sends it.
String inDays(int days) {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day + days,
    12,
  ).toUtc().toIso8601String();
}

Map<String, Object?> invitation(String id, String email, {int days = 5}) => {
  'id': id,
  'email': email,
  'expires_at': inDays(days),
};

/// The owner's family waiting on [invitations].
Map<String, Object?> waitingOn(List<Map<String, Object?>> invitations) => {
  ...ownerFamily,
  'pending_invitations': invitations.length,
  'invitations': invitations,
};

/// `/familia/convites` as the owner, over an API that invites and cancels
/// as the server would, unless [answer] answers instead.
Future<Harness> invitations(
  WidgetTester tester, {
  Map<String, Object?>? family,
  FutureOr<http.Response> Function(http.Request)? answer,
  Size size = const Size(390, 844),
}) async {
  late final Harness h;
  var held = [invitation('i1', 'carla@example.com')];
  h = Harness(
    signedIn: true,
    api: (req) {
      if (answer != null) return answer(req);
      if (req.method == 'POST' && req.url.path == '/v1/family/invitations') {
        final email = (jsonDecode(req.body) as Map)['email'] as String;
        final sent = invitation('i${held.length + 2}', email.toLowerCase());
        held = [...held, sent];
        h.family = waitingOn(held);
        return json(201, sent);
      }
      if (req.method == 'DELETE') {
        final id = req.url.pathSegments.last;
        held = held.where((i) => i['id'] != id).toList();
        h.family = waitingOn(held);
        return http.Response('', 204);
      }
      return http.Response('', 204);
    },
  )..family = family ?? waitingOn(held);
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: '/familia/convites', size: size);
  return h;
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> typeEmail(WidgetTester tester, String email) async {
  await tester.enterText(find.byType(TextField), email);
  await tester.pumpAndSettle();
}

VoidCallback? sendOf(WidgetTester tester) => tester
    .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Enviar convite'))
    .onPressed;

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  test('the adults\' limit names the real cap, invitations included', () {
    expect(Copy.adultsFull, contains('$kMaxAdults adultos'));
    expect(Copy.adultsFull, contains('convites'));
  });

  group('the pending invitations', () {
    testWidgets('each by email with its expiry and Cancelar convite', (
      tester,
    ) async {
      await invitations(
        tester,
        family: waitingOn([
          invitation('i1', 'carla@example.com'),
          invitation('i2', 'davi@example.com', days: 1),
        ]),
      );

      expect(find.text('Convites'), findsOneWidget);
      expect(findAddress('carla@example.com'), findsOneWidget);
      expect(find.text('expira em 5 dias'), findsOneWidget);
      expect(findAddress('davi@example.com'), findsOneWidget);
      expect(find.text('expira amanhã'), findsOneWidget);
      expect(find.text('Cancelar convite'), findsNWidgets(2));
      expect(
        tester.getTopLeft(find.text('Cancelar convite').first).dx,
        tester.getTopLeft(findAddress('carla@example.com')).dx,
      );
      expect(find.text('4 de 6 vagas: 2 adultos e 2 convites'), findsOneWidget);
    });

    testWidgets('none: one line on what an invitation does', (tester) async {
      await invitations(tester, family: waitingOn([]));

      expect(find.text(noInvitations), findsOneWidget);
      expect(find.text('Cancelar convite'), findsNothing);
    });

    testWidgets('Cancelar convite cancels at once and refreshes the list', (
      tester,
    ) async {
      final h = await invitations(tester);

      await tapOn(tester, find.text('Cancelar convite'));

      expect(h.actions, ['DELETE /v1/family/invitations/i1']);
      expect(findAddress('carla@example.com'), findsNothing);
      expect(
        find.text(
          'Cancelamos o convite para ${addressBreaks('carla@example.com')}.',
        ),
        findsOneWidget,
      );
      expect(find.text(noInvitations), findsOneWidget);
    });

    testWidgets('an invitation already gone says so and refreshes', (
      tester,
    ) async {
      late Harness h;
      h = await invitations(
        tester,
        answer: (_) {
          h.family = waitingOn([]);
          return problem(404, 'not_found');
        },
      );

      await tapOn(tester, find.text('Cancelar convite'));

      expect(
        find.text(
          Copy.forError(const ApiError(status: 404, code: 'not_found')),
        ),
        findsOneWidget,
      );
      expect(findAddress('carla@example.com'), findsNothing);
    });

    testWidgets('back returns to the family home', (tester) async {
      final h = await invitations(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
    });
  });

  group('Convidar responsável', () {
    testWidgets('an email field, and Enviar convite waits for an address', (
      tester,
    ) async {
      await invitations(tester);

      expect(find.byType(EmailField), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.keyboardType, TextInputType.emailAddress);
      expect(field.autofillHints, [AutofillHints.email]);
      expect(sendOf(tester), isNull);
      expect(find.text(typeAnEmail), findsOneWidget);

      await typeEmail(tester, 'dani@example.com');
      expect(sendOf(tester), isNotNull);
      expect(find.text(typeAnEmail), findsNothing);
    });

    testWidgets('sends the trimmed address, confirms it, and lists the '
        'invitation', (tester) async {
      final h = await invitations(tester);

      await typeEmail(tester, '  dani@example.com ');
      await tapOn(tester, find.text('Enviar convite'));

      expect(h.actions, [
        'POST /v1/family/invitations {"email":"dani@example.com"}',
      ]);
      expect(
        find.text(
          'Enviamos o convite para ${addressBreaks('dani@example.com')}.',
        ),
        findsOneWidget,
      );
      expect(findAddress('dani@example.com'), findsOneWidget);
      expect(find.text('4 de 6 vagas: 2 adultos e 2 convites'), findsOneWidget);
      expect(fieldText(tester), isEmpty);
    });

    testWidgets('the confirmation is the same for every address, worded '
        'from what was typed', (tester) async {
      await invitations(
        tester,
        answer: (_) => json(201, invitation('i9', 'someone@else.example')),
      );

      for (final email in ['Eva@Example.com', 'nova@example.org']) {
        await typeEmail(tester, email);
        await tapOn(tester, find.text('Enviar convite'));

        expect(
          find.text('Enviamos o convite para ${addressBreaks(email)}.'),
          findsOneWidget,
        );
        final shown = 'Enviamos o convite para ${addressBreaks(email)}.';
        expect(
          tester.widget<Text>(find.text(shown)).semanticsLabel,
          'Enviamos o convite para $email.',
        );
      }
    });

    for (final (code, status, words) in [
      (
        'already_member',
        409,
        Copy.forError(const ApiError(status: 409, code: 'already_member')),
      ),
      ('limit_reached', 409, Copy.adultsFull),
    ]) {
      testWidgets('$code shows its copy and keeps the email', (tester) async {
        await invitations(tester, answer: (_) => problem(status, code));

        await typeEmail(tester, 'bia@example.com');
        await tapOn(tester, find.text('Enviar convite'));

        expect(find.text(words), findsOneWidget);
        expect(fieldText(tester), 'bia@example.com');
        expect(find.textContaining('Enviamos'), findsNothing);
      });
    }

    testWidgets('rate_limited counts down, keeps the email and sending '
        'waits', (tester) async {
      await invitations(
        tester,
        answer: (_) =>
            problem(429, 'rate_limited', headers: {'retry-after': '42'}),
      );

      await typeEmail(tester, 'dani@example.com');
      await tapOn(tester, find.text('Enviar convite'));

      expect(find.textContaining('42 s'), findsOneWidget);
      expect(fieldText(tester), 'dani@example.com');
      expect(sendOf(tester), isNull);

      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('41 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 42));
      expect(sendOf(tester), isNotNull);
    });

    testWidgets('not_owner (ownership passed elsewhere) returns home, which '
        'says only the owner can, once', (tester) async {
      late Harness h;
      h = await invitations(
        tester,
        answer: (_) {
          h.family = {...ownerFamily, 'role': 'guardian', 'invitations': null};
          return problem(403, 'not_owner');
        },
      );

      await typeEmail(tester, 'dani@example.com');
      await tapOn(tester, find.text('Enviar convite'));

      final notOwner = Copy.forError(
        const ApiError(status: 403, code: 'not_owner'),
      );
      expect(h.location(tester), '/');
      expect(find.text(notOwner), findsOneWidget);
      await tapOn(tester, find.text('Responsáveis'));
      await tapOn(tester, find.byTooltip('Voltar'));
      expect(h.location(tester), '/');
      expect(find.text(notOwner), findsNothing);
    });

    testWidgets('a dropped connection keeps the email', (tester) async {
      await invitations(
        tester,
        answer: (_) => throw http.ClientException('down'),
      );

      await typeEmail(tester, 'dani@example.com');
      await tapOn(tester, find.text('Enviar convite'));

      expect(find.text(Copy.genericRetry), findsOneWidget);
      expect(fieldText(tester), 'dani@example.com');
    });

    testWidgets('at six adults, sending is disabled and says why', (
      tester,
    ) async {
      await invitations(
        tester,
        family: waitingOn([
          for (var i = 0; i < 4; i++) invitation('i$i', 'p$i@example.com'),
        ]),
      );

      await typeEmail(tester, 'dani@example.com');

      expect(find.text('6 de 6 vagas: 2 adultos e 4 convites'), findsOneWidget);
      expect(sendOf(tester), isNull);
      expect(find.text(Copy.adultsFull), findsOneWidget);
    });
  });
}

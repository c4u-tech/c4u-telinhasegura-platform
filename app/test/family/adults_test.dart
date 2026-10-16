import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/family/adults_screen.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import 'fixtures.dart';
import '../design/pump.dart' show findAddress;

const ana = {
  'account_id': 'a1',
  'email': 'ana@example.com',
  'role': 'owner',
  'joined_at': '2026-10-03T12:00:00Z',
};
const bia = {
  'account_id': 'a2',
  'email': 'bia@example.com',
  'role': 'guardian',
  'joined_at': '2026-10-03T13:00:00Z',
};

/// The family as ana sees it after handing it to bia.
final handedToBia = <String, Object?>{
  ...ownerFamily,
  'role': 'guardian',
  'members': [
    {...bia, 'role': 'owner'},
    {...ana, 'role': 'guardian'},
  ],
  'invitations': null,
};

/// `/familia/responsaveis` as ana (or bia's guardian, [family]) over an
/// API that removes, hands over and leaves as the server would, unless
/// [answer] answers instead.
Future<Harness> adults(
  WidgetTester tester, {
  Map<String, Object?> family = ownerFamily,
  FutureOr<http.Response> Function(http.Request)? answer,
  bool reauth = false,
}) async {
  late final Harness h;
  var confirmed = !reauth;
  h = Harness(
    signedIn: true,
    api: (req) {
      if (req.url.path == '/v1/session/reauth') {
        confirmed = true;
        return http.Response('', 204);
      }
      if (answer != null) return answer(req);
      switch ((req.method, req.url.path)) {
        case ('DELETE', '/v1/family/members/a2'):
          h.family = {
            ...ownerFamily,
            'members': [ana],
          };
          return http.Response('', 204);
        case ('POST', '/v1/family/owner'):
          if (!confirmed) return problem(403, 'reauth_required');
          h.family = handedToBia;
          return json(200, handedToBia);
        case ('POST', '/v1/family/leave'):
          h.family = null;
          return http.Response('', 204);
      }
      return http.Response('', 204);
    },
  )..family = family;
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: '/familia/responsaveis');
  return h;
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The words of the open confirmation.
String confirmationWords(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(DestructiveConfirmation),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data ?? '')
    .join(' ')
    // An address there is shown with its break marks.
    .replaceAll(RegExp('[\u200B\u2060]'), '');

Finder confirmButton(String label) => find.descendant(
  of: find.byType(DestructiveConfirmation),
  matching: find.widgetWithText(PrimaryButton, label),
);

/// Opens bia's actions and picks [action].
Future<void> onBia(WidgetTester tester, String action) async {
  await tapOn(
    tester,
    find.widgetWithText(DoorRow, addressBreaks('bia@example.com')),
  );
  await tapOn(
    tester,
    find.descendant(
      of: find.byType(GuardianActions),
      matching: find.text(action),
    ),
  );
}

void main() {
  group('the members', () {
    testWidgets('each by email, the owner marked "titular" and the caller '
        '"você", in words', (tester) async {
      final semantics = tester.ensureSemantics();
      await adults(tester);

      expect(find.text('Responsáveis'), findsOneWidget);
      expect(findAddress('ana@example.com'), findsOneWidget);
      expect(findAddress('bia@example.com'), findsOneWidget);
      expect(find.text('titular · você'), findsOneWidget);
      expect(find.text('responsável'), findsOneWidget);
      expect(
        find.bySemanticsLabel('ana@example.com, titular, você'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('the capacity counts members plus pending invitations', (
      tester,
    ) async {
      await adults(tester);

      final capacity = tester.widget<CapacityRow>(find.byType(CapacityRow));
      expect((capacity.filled, capacity.total), (3, 6));
      expect(find.text('3 de 6 vagas: 2 adultos e 1 convite'), findsOneWidget);
    });

    testWidgets('back returns to the family home', (tester) async {
      final h = await adults(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
    });
  });

  group('the owner', () {
    testWidgets('acts on each guardian, never on their own row', (
      tester,
    ) async {
      await adults(tester);

      expect(
        find.widgetWithText(DoorRow, addressBreaks('bia@example.com')),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(DoorRow, addressBreaks('ana@example.com')),
        findsNothing,
      );

      await tapOn(
        tester,
        find.widgetWithText(DoorRow, addressBreaks('bia@example.com')),
      );

      final actions = find.byType(GuardianActions);
      expect(actions, findsOneWidget);
      for (final words in [
        addressBreaks('bia@example.com'),
        'Tornar titular',
        'Remover',
      ]) {
        expect(
          find.descendant(of: actions, matching: find.text(words)),
          findsOneWidget,
        );
      }
      // Remover starts on the column edge, like the email above it.
      expect(
        tester.getTopLeft(find.text('Remover')).dx,
        tester.getTopLeft(find.byType(OutlinedButton)).dx,
      );
    });

    testWidgets('sees Convidar responsável, which opens the invitations, '
        'and how to leave instead of Sair da família', (tester) async {
      final h = await adults(tester);

      expect(find.text('Sair da família'), findsNothing);
      expect(find.text(ownerLeaves), findsOneWidget);

      await tapOn(tester, find.text('Convidar responsável'));

      expect(h.location(tester), '/familia/convites');
    });

    testWidgets('alone, is told to invite someone or delete the family', (
      tester,
    ) async {
      await adults(
        tester,
        family: {
          ...ownerFamily,
          'members': [ana],
        },
      );

      expect(find.text(ownerAlone), findsOneWidget);
      expect(find.byType(DoorRow), findsNothing);
    });
  });

  group('Remover', () {
    testWidgets('asks first, naming the guardian', (tester) async {
      final h = await adults(tester);

      await onBia(tester, 'Remover');

      expect(find.byType(DestructiveConfirmation), findsOneWidget);
      expect(confirmationWords(tester), contains('bia@example.com'));
      expect(h.actions, isEmpty);
    });

    testWidgets('sets the address in its title and text by the Plain '
        'Address Rule: break marks shown, read plain', (tester) async {
      final semantics = tester.ensureSemantics();
      await adults(tester);

      await onBia(tester, 'Remover');

      final bia = addressBreaks('bia@example.com');
      expect(find.text('Remover $bia?'), findsOneWidget);
      expect(find.bySemanticsLabel('Remover bia@example.com?'), findsOneWidget);
      expect(find.textContaining('$bia deixa de fazer parte'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^bia@example\.com deixa de fazer parte'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('cancelling removes nobody', (tester) async {
      final h = await adults(tester);

      await onBia(tester, 'Remover');
      await tapOn(tester, find.text('Cancelar'));

      expect(find.byType(DestructiveConfirmation), findsNothing);
      expect(h.actions, isEmpty);
      expect(findAddress('bia@example.com'), findsOneWidget);
    });

    testWidgets('confirming removes the guardian and refreshes the list', (
      tester,
    ) async {
      final h = await adults(tester);

      await onBia(tester, 'Remover');
      await tapOn(tester, confirmButton('Remover'));

      expect(h.actions, ['DELETE /v1/family/members/a2']);
      expect(find.byType(GuardianActions), findsNothing);
      expect(
        find.widgetWithText(DoorRow, addressBreaks('bia@example.com')),
        findsNothing,
      );
      expect(
        find.text('Removemos ${addressBreaks('bia@example.com')} da família.'),
        findsOne,
      );
      expect(find.text('2 de 6 vagas: 1 adulto e 1 convite'), findsOneWidget);
    });

    testWidgets('not_owner refreshes the family and says only the owner can', (
      tester,
    ) async {
      late Harness h;
      h = await adults(
        tester,
        answer: (_) {
          h.family = handedToBia;
          return problem(403, 'not_owner');
        },
      );

      await onBia(tester, 'Remover');
      await tapOn(tester, confirmButton('Remover'));

      expect(find.text(Copy.forError(_err('not_owner'))), findsOneWidget);
      expect(find.text('Sair da família'), findsOneWidget);
      expect(find.byType(DoorRow), findsNothing);
    });

    testWidgets('a dropped connection says so and keeps the guardian', (
      tester,
    ) async {
      await adults(tester, answer: (_) => throw http.ClientException('down'));

      await onBia(tester, 'Remover');
      await tapOn(tester, confirmButton('Remover'));

      expect(find.text(Copy.genericRetry), findsOneWidget);
      expect(
        find.widgetWithText(DoorRow, addressBreaks('bia@example.com')),
        findsOneWidget,
      );
    });

    testWidgets('while pending, the guardian\'s row shows progress and '
        'waits', (tester) async {
      final reply = Completer<http.Response>();
      await adults(tester, answer: (_) => reply.future);

      await onBia(tester, 'Remover');
      await tester.ensureVisible(confirmButton('Remover'));
      await tester.pumpAndSettle();
      await tester.tap(confirmButton('Remover'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final row = tester.widget<DoorRow>(
        find.widgetWithText(DoorRow, addressBreaks('bia@example.com')),
      );
      expect(row.busy, isTrue);
      expect(
        find.descendant(
          of: find.widgetWithText(DoorRow, addressBreaks('bia@example.com')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      reply.complete(http.Response('', 204));
      await tester.pumpAndSettle();
    });
  });

  group('Tornar titular', () {
    testWidgets('asks first, naming the guardian and saying the caller '
        'becomes a guardian', (tester) async {
      final h = await adults(tester);

      await onBia(tester, 'Tornar titular');

      final words = confirmationWords(tester);
      expect(words, contains('bia@example.com'));
      expect(words, contains('Você passa a ser responsável'));
      expect(h.actions, isEmpty);
    });

    testWidgets('sets the address in its title and text by the Plain '
        'Address Rule', (tester) async {
      final semantics = tester.ensureSemantics();
      await adults(tester);

      await onBia(tester, 'Tornar titular');

      final bia = addressBreaks('bia@example.com');
      expect(find.text('Tornar $bia titular?'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Tornar bia@example.com titular?'),
        findsOneWidget,
      );
      expect(find.textContaining('$bia passa a ser'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^bia@example\.com passa a ser')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('confirming asks to confirm it is you, hands the family '
        'over, and shows the new roles', (tester) async {
      final h = await adults(tester, reauth: true);

      await onBia(tester, 'Tornar titular');
      await tapOn(tester, confirmButton('Tornar titular'));
      expect(find.byType(ReauthPrompt), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'uma senha longa');
      await tester.pumpAndSettle();
      await tapOn(tester, find.text('Confirmar'));

      expect(h.actions.map((a) => a.split(' {').first), [
        'POST /v1/family/owner',
        'POST /v1/session/reauth',
        'POST /v1/family/owner',
      ]);
      expect(
        jsonDecode(h.actions.last.substring(h.actions.last.indexOf('{'))),
        {'account_id': 'a2'},
      );
      expect(
        find.text(
          '${addressBreaks('bia@example.com')} agora é titular da família.',
        ),
        findsOne,
      );
      expect(find.text('responsável · você'), findsOneWidget);
      expect(find.text('titular'), findsOneWidget);
      expect(find.byType(DoorRow), findsNothing);
      expect(find.text('Sair da família'), findsOneWidget);
      expect(find.text('Convidar responsável'), findsNothing);
    });
  });

  group('a guardian', () {
    final guardian = <String, Object?>{
      ...ownerFamily,
      'role': 'guardian',
      'members': [
        {...bia, 'role': 'owner'},
        {...ana, 'role': 'guardian'},
      ],
      'invitations': null,
    };

    testWidgets('sees the members without actions on them', (tester) async {
      await adults(tester, family: guardian);

      expect(find.byType(DoorRow), findsNothing);
      expect(findAddress('bia@example.com'), findsOneWidget);
      expect(find.text('Convidar responsável'), findsNothing);
      expect(find.text(ownerLeaves), findsNothing);
    });

    testWidgets('Sair da família asks first, then leaves for the first use', (
      tester,
    ) async {
      final h = await adults(tester, family: guardian);

      await tapOn(tester, find.text('Sair da família'));
      expect(find.byType(DestructiveConfirmation), findsOneWidget);
      expect(h.actions, isEmpty);

      await tapOn(tester, confirmButton('Sair da família'));

      expect(h.actions, ['POST /v1/family/leave']);
      expect(h.location(tester), '/');
      expect(find.text('Começar minha família'), findsOneWidget);
      expect(find.text(Copy.forError(_err('no_family'))), findsNothing);
    });

    testWidgets('cancelling stays in the family', (tester) async {
      final h = await adults(tester, family: guardian);

      await tapOn(tester, find.text('Sair da família'));
      await tapOn(tester, find.text('Cancelar'));

      expect(h.actions, isEmpty);
      expect(h.location(tester), '/familia/responsaveis');
    });

    testWidgets('owner_must_transfer says so and shows the roles again', (
      tester,
    ) async {
      late Harness h;
      h = await adults(
        tester,
        family: guardian,
        answer: (_) {
          h.family = ownerFamily;
          return problem(409, 'owner_must_transfer');
        },
      );

      await tapOn(tester, find.text('Sair da família'));
      await tapOn(tester, confirmButton('Sair da família'));

      expect(
        find.text(Copy.forError(_err('owner_must_transfer'))),
        findsOneWidget,
      );
      expect(find.text(ownerLeaves), findsOneWidget);
      expect(h.location(tester), '/familia/responsaveis');
    });
  });

  testWidgets('no_family on a write returns home with the calm notice', (
    tester,
  ) async {
    late Harness h;
    h = await adults(
      tester,
      answer: (_) {
        h.family = null;
        return problem(404, 'no_family');
      },
    );

    await onBia(tester, 'Remover');
    await tapOn(tester, confirmButton('Remover'));

    expect(h.location(tester), '/');
    expect(find.text(Copy.forError(_err('no_family'))), findsOneWidget);
  });
}

ApiError _err(String code) => ApiError(status: 400, code: code);

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/account/account_screen.dart';
import 'package:telinha_segura/account/delete_account_screen.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/apple_id_tokens.dart';
import 'package:telinha_segura/auth/provider_authenticator.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/family/adults_screen.dart';
import 'package:telinha_segura/family/delete_family_screen.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/family/invitations_screen.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';

const deleteRequest = 'DELETE /v1/account';

/// The owner's family but its role and members (a const map cannot
/// spread a key it then sets again).
const familyRest = {
  'id': 'f1',
  'minors': [
    {
      'id': 'm1',
      'nickname': 'Lia',
      'avatar': 'fox',
      'age_band': '5-8',
      'created_at': '2026-10-03T12:30:00Z',
      'updated_at': '2026-10-03T12:30:00Z',
    },
  ],
  'pending_invitations': 0,
  'invitations': <Object>[],
};

/// Ana is a guardian of Bia's family.
const memberFamily = {
  ...familyRest,
  'role': 'guardian',
  'members': [
    {
      'account_id': 'a2',
      'email': 'bia@example.com',
      'role': 'owner',
      'joined_at': '2026-10-03T12:00:00Z',
    },
    {
      'account_id': 'a1',
      'email': 'ana@example.com',
      'role': 'guardian',
      'joined_at': '2026-10-03T13:00:00Z',
    },
  ],
};

/// Ana owns a family nobody else cares for.
const ownerAloneFamily = {
  ...familyRest,
  'role': 'owner',
  'members': [
    {
      'account_id': 'a1',
      'email': 'ana@example.com',
      'role': 'owner',
      'joined_at': '2026-10-03T12:00:00Z',
    },
  ],
};

/// `/conta/excluir` for Ana in [family] (none when null). The deletion
/// answers [answer] (204 by default, after a re-authentication when
/// [reauth]).
Future<Harness> deleteScreen(
  WidgetTester tester, {
  Map<String, Object?>? family = memberFamily,
  FutureOr<http.Response> Function(http.Request)? answer,
  bool reauth = false,
  bool unverified = false,
  ProviderSettings settings = noProviders,
}) async {
  var confirmed = !reauth;
  final h =
      Harness(
          signedIn: true,
          settings: settings,
          api: (req) {
            if (req.url.path == '/v1/sessions') {
              return json(200, {'sessions': <Object>[]});
            }
            if (req.url.path == '/v1/session/reauth') {
              confirmed = true;
              return http.Response('', 204);
            }
            if (answer != null) return answer(req);
            if (req.method == 'DELETE' && req.url.path == '/v1/account') {
              return confirmed
                  ? http.Response('', 204)
                  : problem(403, 'reauth_required');
            }
            return http.Response('', 204);
          },
        )
        ..family = family
        ..unverified = unverified;
  await h.pump(tester, initial: '/conta/excluir');
  return h;
}

Finder get deleteButton =>
    find.widgetWithText(PrimaryButton, 'Excluir minha conta');

VoidCallback? deleteOf(WidgetTester tester) =>
    tester.widget<PrimaryButton>(deleteButton).onPressed;

Finder get transferDoor =>
    find.widgetWithText(DoorRow, 'Tornar outro adulto titular');

Finder get inviteDoor => find.widgetWithText(DoorRow, 'Convidar outro adulto');

Finder get deleteFamilyDoor =>
    find.widgetWithText(QuietAction, 'Excluir a família');

String words(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.semanticsLabel ?? t.data ?? '')
    .join(' ');

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Declares, then confirms the deletion.
Future<void> confirmDeletion(WidgetTester tester) async {
  await tapOn(tester, find.byType(DeclarationRow));
  await tapOn(tester, deleteButton);
}

/// The lines of the "what goes" list, in order, as they are read.
List<String> bullets(WidgetTester tester) => [
  for (final item in tester.widgetList<BulletItem>(find.byType(BulletItem)))
    item.semanticsLabel ?? item.text,
];

/// The text read as [line], however its addresses are set to break.
Finder shown(String line) => find.byWidgetPredicate(
  (w) => w is Text && (w.semanticsLabel ?? w.data) == line,
);

/// The top of the text [text], to read what comes after what.
double topOf(WidgetTester tester, String text) =>
    tester.getTopLeft(shown(text)).dy;

void main() {
  testWidgets('a member reads what goes as a list under its lead, then what '
      'stays apart, below it', (tester) async {
    await deleteScreen(tester);

    expect(find.text('Excluir sua conta apaga na hora:'), findsOneWidget);
    expect(bullets(tester), [
      'Sua conta, com o e-\u2060mail ana@example.com, e as formas de entrar '
          'nela',
      'Os aparelhos conectados, que saem da conta',
      'Seu lugar na família, e com ele o acesso às crianças',
    ]);
    const stays = [
      'A família e as crianças continuam, com bia@example.com como '
          'titular.',
      'O histórico da conta fica guardado sem seu e-\u2060mail, sem ligação '
          'com você.',
      'Se quiser voltar depois, é só criar uma conta nova.',
    ];
    final lastBullet = tester.getBottomLeft(find.byType(BulletItem).last).dy;
    for (final line in stays) {
      expect(shown(line), findsOneWidget);
      expect(
        find.ancestor(of: shown(line), matching: find.byType(BulletItem)),
        findsNothing,
        reason: 'what stays is not in the list of what goes',
      );
      expect(topOf(tester, line), greaterThan(lastBullet));
    }
    expect(
      topOf(tester, 'Excluir sua conta apaga na hora:'),
      lessThan(tester.getTopLeft(find.byType(BulletItem).first).dy),
    );
  });

  testWidgets('both addresses are set to break at their safe points', (
    tester,
  ) async {
    await deleteScreen(tester);

    expect(
      find.textContaining(addressBreaks('ana@example.com')),
      findsOneWidget,
    );
    expect(
      find.textContaining(addressBreaks('bia@example.com')),
      findsOneWidget,
    );
  });

  testWidgets('without a family, the list holds the account and the '
      'devices, and the history and the way back stay', (tester) async {
    await deleteScreen(tester, family: null);

    expect(bullets(tester), [
      'Sua conta, com o e-\u2060mail ana@example.com, e as formas de entrar '
          'nela',
      'Os aparelhos conectados, que saem da conta',
    ]);
    expect(find.textContaining('histórico da conta'), findsOneWidget);
    expect(find.textContaining('criar uma conta nova'), findsOneWidget);
  });

  testWidgets('a member reads what goes, and that the family and the '
      'children stay with the titular; Excluir minha conta waits on the '
      'declaration', (tester) async {
    await deleteScreen(tester);

    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    final said = words(tester);
    expect(said, contains('ana@example.com'));
    expect(said, contains('formas de entrar'));
    expect(said, contains('aparelhos conectados'));
    expect(said, contains('Seu lugar na família'));
    expect(said, contains('A família e as crianças continuam'));
    expect(said, contains('bia@example.com'));
    expect(said, contains('histórico da conta'));
    expect(deleteButton, findsOneWidget);
    expect(deleteOf(tester), isNull);
    expect(find.text(declarationHint), findsOneWidget);
    expect(transferDoor, findsNothing);
    expect(deleteFamilyDoor, findsNothing);

    await tapOn(tester, find.byType(DeclarationRow));
    expect(deleteOf(tester), isNotNull);
  });

  for (final (state, unverified) in [
    ('without a family', false),
    ('with the email unverified', true),
  ]) {
    testWidgets('$state, the list is shorter: nothing about a family', (
      tester,
    ) async {
      await deleteScreen(tester, family: null, unverified: unverified);

      final said = words(tester);
      expect(said, contains('formas de entrar'));
      expect(said, isNot(contains('família')));
      expect(deleteButton, findsOneWidget);
    });
  }

  testWidgets('confirming deletes the account and lands on the entry '
      'screen, signed out, with the calm notice', (tester) async {
    final h = await deleteScreen(tester);

    await confirmDeletion(tester);

    expect(h.actions, [deleteRequest]);
    expect(h.services.client.status.value, AuthStatus.signedOut);
    expect(h.location(tester), '/entrar');
    expect(find.byType(EntryScreen), findsOneWidget);
    expect(find.widgetWithText(Notice, accountDeleted), findsOneWidget);
    expect(accountDeleted, 'Sua conta foi excluída.');
  });

  testWidgets('reauth_required asks to confirm it is you, then retries once', (
    tester,
  ) async {
    final h = await deleteScreen(tester, reauth: true);

    await confirmDeletion(tester);
    expect(find.byType(ReauthPrompt), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'uma senha longa');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(h.actions.map((a) => a.split(' {').first), [
      deleteRequest,
      'POST /v1/session/reauth',
      deleteRequest,
    ]);
    expect(find.widgetWithText(Notice, accountDeleted), findsOneWidget);
  });

  testWidgets('a cancelled prompt keeps the screen, quietly', (tester) async {
    final h = await deleteScreen(tester, reauth: true);

    await confirmDeletion(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(h.actions, [deleteRequest]);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(find.byType(ErrorNote), findsNothing);
    expect(deleteOf(tester), isNotNull);
    expect(h.services.entryNotice, isNull);
  });

  testWidgets('an owner is offered no deletion: the family needs a titular '
      'first, with both doors', (tester) async {
    final h = await deleteScreen(tester, family: ownerFamily);

    expect(deleteButton, findsNothing);
    expect(find.byType(DeclarationRow), findsNothing);
    expect(words(tester), contains('titular'));
    expect(transferDoor, findsOneWidget);
    expect(tester.widget<QuietAction>(deleteFamilyDoor).destructive, isTrue);
    expect(h.actions, isEmpty);
  });

  testWidgets('Tornar outro adulto titular opens the adults', (tester) async {
    final h = await deleteScreen(tester, family: ownerFamily);

    await tapOn(tester, transferDoor);

    expect(h.location(tester), '/familia/responsaveis');
    expect(find.byType(AdultsScreen), findsOneWidget);
  });

  testWidgets('Excluir a família opens the family deletion', (tester) async {
    final h = await deleteScreen(tester, family: ownerFamily);

    await tapOn(tester, find.text('Excluir a família'));

    expect(h.location(tester), '/familia/excluir');
    expect(find.byType(DeleteFamilyScreen), findsOneWidget);
  });

  testWidgets('an owner alone gets no transfer door, a door to invite '
      'another adult above the family deletion', (tester) async {
    await deleteScreen(tester, family: ownerAloneFamily);

    expect(transferDoor, findsNothing);
    expect(inviteDoor, findsOneWidget);
    expect(deleteFamilyDoor, findsOneWidget);
    expect(
      tester.getBottomLeft(inviteDoor).dy,
      lessThan(tester.getTopLeft(deleteFamilyDoor).dy),
    );
    expect(deleteButton, findsNothing);
  });

  testWidgets('Convidar outro adulto opens the invitations', (tester) async {
    final h = await deleteScreen(tester, family: ownerAloneFamily);

    await tapOn(tester, inviteDoor);

    expect(h.location(tester), '/familia/convites');
    expect(find.byType(InvitationsScreen), findsOneWidget);
  });

  testWidgets('an owner with other adults gets the transfer door, not the '
      'invite one', (tester) async {
    await deleteScreen(tester, family: ownerFamily);

    expect(transferDoor, findsOneWidget);
    expect(inviteDoor, findsNothing);
  });

  testWidgets('while the family loads, neither state shows', (tester) async {
    final read = Completer<http.Response>();
    final h = Harness(signedIn: true, api: (req) => http.Response('', 204))
      ..familyRead = () => read.future;
    await h.pump(tester, initial: '/conta/excluir');

    expect(find.byType(FamilyPlaceholder), findsOneWidget);
    expect(deleteButton, findsNothing);
    expect(transferDoor, findsNothing);
    expect(deleteFamilyDoor, findsNothing);

    read.complete(json(200, ownerFamily));
    await tester.pumpAndSettle();
    expect(transferDoor, findsOneWidget);
  });

  testWidgets('a failed family read offers to try again', (tester) async {
    var fail = true;
    final h = Harness(signedIn: true);
    h.familyRead = () =>
        fail ? problem(503, 'unavailable') : json(200, memberFamily);
    await h.pump(tester, initial: '/conta/excluir');

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOne);
    expect(deleteButton, findsNothing);
    fail = false;
    await tapOn(tester, find.text('Tentar de novo'));
    expect(deleteButton, findsOneWidget);
  });

  testWidgets('owner_must_transfer reads the family again and shows the '
      'owner\'s state', (tester) async {
    late final Harness h;
    h = await deleteScreen(
      tester,
      answer: (req) {
        if (req.method != 'DELETE') return http.Response('', 204);
        // Ownership passed to Ana elsewhere meanwhile.
        h.family = ownerFamily;
        return problem(409, 'owner_must_transfer');
      },
    );

    await confirmDeletion(tester);

    expect(h.calls.where((c) => c == 'GET /v1/family'), hasLength(2));
    expect(deleteButton, findsNothing);
    expect(transferDoor, findsOneWidget);
    expect(deleteFamilyDoor, findsOneWidget);
    expect(find.byType(ErrorNote), findsNothing);
    expect(h.services.client.status.value, AuthStatus.signedIn);
    expect(h.services.entryNotice, isNull);
  });

  testWidgets('after the owner deletes the family, the screen offers the '
      'account\'s deletion, without a family', (tester) async {
    late final Harness h;
    h = await deleteScreen(
      tester,
      family: ownerFamily,
      answer: (req) {
        if (req.method == 'DELETE' && req.url.path == '/v1/family') {
          h.family = null;
        }
        return http.Response('', 204);
      },
    );

    await tapOn(tester, find.text('Excluir a família'));
    await tapOn(tester, find.byType(DeclarationRow));
    await tapOn(tester, find.widgetWithText(PrimaryButton, 'Excluir família'));
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/conta/excluir');
    await tester.pumpAndSettle();

    expect(deleteButton, findsOneWidget);
    expect(words(tester), isNot(contains('família')));
  });

  testWidgets('a network failure or 5xx says so and keeps the screen', (
    tester,
  ) async {
    final h = await deleteScreen(
      tester,
      answer: (_) => problem(503, 'unavailable'),
    );

    await confirmDeletion(tester);

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOne);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(deleteOf(tester), isNotNull);
    expect(h.services.entryNotice, isNull);
  });

  testWidgets('rate_limited shows its countdown and waits', (tester) async {
    await deleteScreen(
      tester,
      answer: (_) =>
          problem(429, 'rate_limited', headers: {'retry-after': '90'}),
    );

    await confirmDeletion(tester);

    expect(
      find.widgetWithText(ErrorNote, Copy.retryIn(const Duration(seconds: 90))),
      findsOne,
    );
    expect(deleteOf(tester), isNull);
    await tester.pump(const Duration(seconds: 91));
    expect(deleteOf(tester), isNotNull);
  });

  testWidgets('the button waits, with progress, while the deletion runs', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    await deleteScreen(tester, answer: (_) => answer.future);

    await tapOn(tester, find.byType(DeclarationRow));
    await tester.tap(deleteButton);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Excluir minha conta'), findsOneWidget);
    answer.complete(http.Response('', 204));
    await tester.pumpAndSettle();
  });

  testWidgets('unauthenticated lands on the entry screen, signed out, '
      'without the deletion notice', (tester) async {
    await deleteScreen(tester, answer: (_) => problem(401, 'unauthenticated'));

    await confirmDeletion(tester);

    expect(find.byType(EntryScreen), findsOneWidget);
    expect(find.text(accountDeleted), findsNothing);
  });

  testWidgets('the band\'s back control returns to the account', (
    tester,
  ) async {
    await deleteScreen(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
  });

  group('an Apple-linked account', () {
    const credential = AppleCredential(
      identityToken: 'i',
      authorizationCode: 'c',
    );

    /// The first deletion asks for Apple; the next answers [then].
    Future<Harness> appleScreen(
      WidgetTester tester, {
      http.Response Function()? then,
      ProviderSettings settings = allProviders,
    }) => deleteScreen(
      tester,
      settings: settings,
      answer: (req) {
        if (req.method != 'DELETE') return http.Response('', 204);
        final carried = req.body.contains('"apple"');
        return carried
            ? (then?.call() ?? http.Response('', 204))
            : problem(422, 'apple_reauthorization_required');
      },
    );

    testWidgets('confirms with Apple and deletes', (tester) async {
      final h = await appleScreen(tester);
      h.providers.apple = credential;

      await confirmDeletion(tester);

      expect(h.providers.appleAsked, 1);
      final deletes = h.calls.where((c) => c.startsWith(deleteRequest));
      expect(deletes, hasLength(2));
      expect(deletes.first.trim(), deleteRequest);
      expect(deletes.last, contains('"apple"'));
      expect(deletes.last, contains('"c"'));
      expect(h.location(tester), '/entrar');
      expect(find.widgetWithText(Notice, accountDeleted), findsOneWidget);
    });

    testWidgets('cancelling Apple deletes nothing', (tester) async {
      final h = await appleScreen(tester);
      h.providers.apple = null;

      await confirmDeletion(tester);

      expect(h.calls.where((c) => c.startsWith(deleteRequest)), hasLength(1));
      expect(find.byType(ErrorNote), findsNothing);
      expect(deleteOf(tester), isNotNull);
      await tapOn(tester, deleteButton);
      expect(h.providers.appleAsked, 2);
    });

    testWidgets('Apple off in this build names support', (tester) async {
      final h = await appleScreen(tester, settings: noProviders);

      await confirmDeletion(tester);

      expect(find.widgetWithText(ErrorNote, appleUnavailable), findsOne);
      expect(h.providers.appleAsked, 0);
    });

    testWidgets('Apple refusing shows a retry message and asks again', (
      tester,
    ) async {
      final h = await appleScreen(
        tester,
        then: () => problem(422, 'apple_authorization_invalid'),
      );
      h.providers.apple = credential;

      await confirmDeletion(tester);

      expect(find.widgetWithText(ErrorNote, appleRejected), findsOne);
      expect(h.providers.appleAsked, 1);
      await tapOn(tester, deleteButton);
      expect(h.providers.appleAsked, 2);
      expect(h.calls.where((c) => c.startsWith(deleteRequest)), hasLength(4));
    });

    testWidgets('a credential the API still wants more for is not asked '
        'for again by itself', (tester) async {
      final h = await appleScreen(
        tester,
        then: () => problem(422, 'apple_reauthorization_required'),
      );
      h.providers.apple = credential;

      await confirmDeletion(tester);

      expect(h.providers.appleAsked, 1);
      expect(find.widgetWithText(ErrorNote, appleRejected), findsOne);
    });

    testWidgets('a failing Apple sheet says so, deletes nothing and asks '
        'again on the next tap', (tester) async {
      final h = await appleScreen(tester);
      h.providers.appleError = StateError('state mismatch');

      await confirmDeletion(tester);

      expect(find.widgetWithText(ErrorNote, appleFailed), findsOne);
      expect(h.calls.where((c) => c.startsWith(deleteRequest)), hasLength(1));
      expect(deleteOf(tester), isNotNull);
      await tapOn(tester, deleteButton);
      expect(h.providers.appleAsked, 2);
    });

    testWidgets('the button waits while the Apple sheet is up', (tester) async {
      final h = await appleScreen(tester);
      final sheet = Completer<AppleCredential?>();
      h.providers.appleSheet = sheet;

      await tapOn(tester, find.byType(DeclarationRow));
      await tester.tap(deleteButton);
      await tester.pump();
      await tester.pump();

      expect(h.providers.appleAsked, 1);
      expect(deleteOf(tester), isNull);
      sheet.complete(null);
      await tester.pumpAndSettle();
      expect(deleteOf(tester), isNotNull);
    });

    testWidgets('a different Apple ID gets its own message, not a loop of '
        'retries', (tester) async {
      final h = await appleScreen(
        tester,
        then: () => problem(403, 'apple_identity_mismatch'),
      );
      h.providers.apple = credential;

      await confirmDeletion(tester);

      expect(find.widgetWithText(ErrorNote, appleMismatch), findsOne);
    });
  });
}

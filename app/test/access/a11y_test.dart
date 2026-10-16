import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/provider_sign_in.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/profile_fields.dart' show SelectableRow;
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid_mode/hand_over_screen.dart';
import 'package:telinha_segura/kid/kid_player.dart';
import 'package:telinha_segura/kid/pack_player_screen.dart';
import 'package:telinha_segura/kid/pack_row.dart';
import 'package:telinha_segura/kid/player_keys.dart';
import 'package:telinha_segura/kid/player_screen.dart';
import 'package:telinha_segura/kid/shelves.dart';
import 'package:telinha_segura/kid_mode/kid_mode_screen.dart';
import 'package:telinha_segura/shell/services.dart';
import 'package:telinha_segura/parental/kid_mode_mark.dart';
import 'package:telinha_segura/privacy/export_delivery.dart';

import '../account/account_screen_test.dart' show sessionJson, sessionsAnswer;
import '../account/mfa_fixtures.dart';
import '../curation/approve_screen_test.dart' show approve;
import '../curation/compose_pack_screen_test.dart' as composing;
import '../curation/curation_api_test.dart'
    show rejectionJson, reviewJson, videoJson;
import '../curation/fixtures.dart';
import '../curation/appoint_screen_test.dart' as staffing;
import '../curation/new_suggestion_screen_test.dart' show send;
import '../curation/refuse_screen_test.dart' show refuse;
import '../account/delete_account_screen_test.dart'
    show memberFamily, ownerAloneFamily;
import '../family/fixtures.dart';
import '../parental/fakes.dart';
import '../parental/parental_api_test.dart' show deviceJson, profileJson;
import '../kid_mode/devices_screen_test.dart' show device;
import '../kid/fake_player.dart';
import '../kid/kid_shelves_test.dart' show pixel, twoShelves;
import '../kid/more_time_door_test.dart' show holdExit;
import '../kid/pack_player_test.dart' show packKid;
import '../kid/sleeping_home_test.dart' show day, shelvesOn;
import '../kid_mode/link_code_screen_test.dart' show liveCode;
import '../catalog/fixtures.dart' as catalog;
import '../screentime/fixtures.dart';
import '../screentime/more_time_screen_test.dart' show choose, give;
import '../screentime/time_rules_screen_test.dart' show pick;
import '../staff/account_search_screen_test.dart' as directory;
import '../staff/accounts_api_test.dart' show actionJson, sheetJson;
import 'harness.dart';

/// Every access route, with what it needs in memory.
const routes = {
  '/entrar': null,
  '/entrar/email': null,
  '/criar-conta': null,
  '/verifique-seu-email': null,
  '/verificar-email': null,
  '/esqueci-a-senha': null,
  '/redefinir-senha?token=t': null,
  '/concluir-cadastro': SignupRequired(ticket: 't', email: 'ana@gmail.com'),
  '/vincular-conta': LinkRequired(
    ticket: 't',
    email: 'ana@example.com',
    options: {LinkOption.password, LinkOption.clearPassword},
  ),
};

Future<Harness> openRoute(
  WidgetTester tester,
  String path, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final h = Harness(settings: allProviders);
  h.services.pending.value = routes[path];
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  return h;
}

/// The family home's states, each as the signed-in account sees it.
final homes = <String, void Function(Harness)>{
  'member': (h) => h.family = ownerFamily,
  'guardian': (h) => h.family = {...ownerFamily, 'role': 'guardian'},
  // Tempo de tela is then a row nobody acts on.
  'no children': (h) => h.family = familyWith([]),
  'no family': (h) => h.family = null,
  'email unverified': (h) => h.unverified = true,
  'failed': (h) => h.familyRead = () => problem(503, 'unavailable'),
  // The Sua conta door and the foot name the account.
  'long email': (h) => h
    ..family = ownerFamily
    ..email = longEmail,
  'no family, long email': (h) => h
    ..family = null
    ..email = longEmail,
  // Invitations waiting for the first use.
  'invited once': (h) => h
    ..family = null
    ..api = invitationsFor(['carla@example.com']),
  'invited twice': (h) => h
    ..family = null
    ..api = invitationsFor(['carla@example.com', 'davi@example.com']),
  'invited, long email': (h) => h
    ..family = null
    ..api = invitationsFor([longEmail]),
  // Every curation door.
  'curator and admin': (h) => h
    ..family = ownerFamily
    ..roles = ['admin', 'curator'],
  // The role doors with no family.
  'no family, moderator': (h) => h
    ..family = null
    ..roles = ['moderator'],
  'invited, curator and moderator': (h) => h
    ..family = null
    ..roles = ['curator', 'moderator']
    ..api = invitationsFor(['carla@example.com']),
  // The suspended home, with and without a family; the appeal line
  // names the account.
  'suspended': (h) => h
    ..family = ownerFamily
    ..status = 'suspended',
  'suspended, no family': (h) => h
    ..family = null
    ..status = 'suspended',
  'suspended, long email': (h) => h
    ..family = ownerFamily
    ..status = 'suspended'
    ..email = longEmail,
};

/// `GET /v1/invitations` answering one invitation from each of
/// [inviters].
FutureOr<http.Response> Function(http.Request) invitationsFor(
  List<String> inviters,
) =>
    (req) => req.url.path == '/v1/invitations'
    ? json(200, {
        'invitations': [
          for (final (n, inviter) in inviters.indexed)
            {
              'id': 'i$n',
              'inviter_email': inviter,
              'expires_at': DateTime.now()
                  .add(const Duration(days: 5))
                  .toUtc()
                  .toIso8601String(),
            },
        ],
      })
    : http.Response('', 204);

Future<Harness> openHome(
  WidgetTester tester,
  String state, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final h = Harness(signedIn: true);
  homes[state]!(h);
  await h.pump(tester, initial: '/', size: size, textScale: textScale);
  return h;
}

/// The account index in its states: the family, whether the email waits
/// for its confirmation, and the account's address.
final accountStates = <String, void Function(Harness)>{
  'account': (h) => h.family = ownerFamily,
  'account, no family': (h) => h.family = null,
  'account, email unverified': (h) => h
    ..family = null
    ..unverified = true,
  'account, long email': (h) => h
    ..family = ownerFamily
    ..email = longEmail,
  'account, long email unverified': (h) => h
    ..family = null
    ..unverified = true
    ..email = longEmail,
};

Future<Harness> openAccount(
  WidgetTester tester,
  String state, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final h = Harness(
    signedIn: true,
    api: (req) => req.url.path == '/v1/sessions'
        ? json(200, {
            'sessions': [
              for (var i = 0; i < 3; i++)
                {
                  'id': 's$i',
                  'client': 'web',
                  'device_label': 'Navegador',
                  'created_at': '2026-10-01T12:00:00Z',
                  'last_seen_at': '2026-10-04T12:00:00Z',
                  'current': i == 0,
                },
            ],
          })
        : http.Response('', 204),
  );
  accountStates[state]!(h);
  await h.pump(tester, initial: '/conta', size: size, textScale: textScale);
  return h;
}

/// Enters [text] in the field labelled [label] and taps [action], each
/// scrolled into view first.
Future<void> fillAndTap(
  WidgetTester tester,
  Map<String, String> fields,
  String action,
) async {
  for (final MapEntry(key: label, value: text) in fields.entries) {
    final field = find.widgetWithText(TextField, label);
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
  }
  final button = find.text(action);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> sendNewEmail(WidgetTester tester, [String? to]) => fillAndTap(
  tester,
  {'Novo e-\u2060mail': to ?? 'bia@example.com'},
  'Enviar link',
);

Future<void> changePassword(WidgetTester tester) => fillAndTap(tester, {
  'Senha atual': 'a senha de antes, longa',
  'Nova senha': 'uma senha nova bem longa',
}, 'Trocar senha');

/// The account's task screens in their key states: the path, what their
/// writes answer (204 or 202 when null), whether the account's address is
/// [longEmail], and what to do once it shows.
final accountTasks =
    <
      String,
      (
        String,
        http.Response Function()?,
        bool,
        Future<void> Function(WidgetTester)?,
      )
    >{
      'change email': ('/conta/email', null, false, null),
      'change email, long email': ('/conta/email', null, true, null),
      'change email, invalid': (
        '/conta/email',
        () => problem(422, 'validation'),
        false,
        sendNewEmail,
      ),
      'change email, failed': (
        '/conta/email',
        () => problem(503, 'unavailable'),
        false,
        sendNewEmail,
      ),
      'change email, long email, link sent': (
        '/conta/email',
        null,
        true,
        (t) => sendNewEmail(t, longEmail),
      ),
      'password': ('/conta/senha', null, false, null),
      'password, wrong current': (
        '/conta/senha',
        () => problem(401, 'invalid_credentials'),
        false,
        changePassword,
      ),
      'password, weak': (
        '/conta/senha',
        () => problem(422, 'weak_password', reasons: ['breached']),
        false,
        changePassword,
      ),
      'password, rate limited': (
        '/conta/senha',
        () => problem(429, 'rate_limited', headers: {'retry-after': '90'}),
        false,
        changePassword,
      ),
      'password, changed': ('/conta/senha', null, false, changePassword),
      'password, link sent': (
        '/conta/senha',
        null,
        false,
        (t) => fillAndTap(t, {}, 'Criar uma senha'),
      ),
    };

Future<Harness> openAccountTask(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (path, answer, long, then) = accountTasks[name]!;
  final h = Harness(
    signedIn: true,
    // The index under the task screen reads the sessions.
    api: (req) => req.url.path == '/v1/sessions'
        ? json(200, {'sessions': <Object>[]})
        : answer?.call() ?? http.Response('', 202),
  )..family = ownerFamily;
  if (long) h.email = longEmail;
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  await then?.call(tester);
  return h;
}

/// The connected devices screen in its key states: what the sessions
/// read answers, what the writes answer (204 when null), and what to do
/// once it shows.
final sessionsStates =
    <
      String,
      (
        http.Response Function(),
        http.Response Function()?,
        Future<void> Function(WidgetTester)?,
      )
    >{
      'sessions': (() => sessionsAnswer(3), null, null),
      'sessions, only this device': (() => sessionsAnswer(1), null, null),
      'sessions, unlabelled': (
        () => json(200, {
          'sessions': [
            sessionJson('here', current: true, label: ''),
            sessionJson('phone', client: 'mobile', label: ''),
          ],
        }),
        null,
        null,
      ),
      // The longest labels a sign-in sends (64 characters), one with no
      // space to break at.
      'sessions, long labels': (
        () => json(200, {
          'sessions': [
            sessionJson('here', current: true, label: 'S' * 64),
            sessionJson(
              'phone',
              client: 'mobile',
              label: 'Samsung Internet no Android ${'x' * 36}',
            ),
          ],
        }),
        null,
        null,
      ),
      'sessions, many': (() => sessionsAnswer(24), null, null),
      'sessions, failed read': (() => problem(503, 'unavailable'), null, null),
      'sessions, end failed': (
        () => sessionsAnswer(3),
        () => problem(503, 'unavailable'),
        (t) async {
          await t.tap(find.text('Encerrar').first);
          await t.pumpAndSettle();
        },
      ),
      'sessions, others ended': (
        () => sessionsAnswer(3),
        null,
        (t) => fillAndTap(t, {}, 'Sair dos outros aparelhos'),
      ),
      'sessions, confirm all': (
        () => sessionsAnswer(3),
        null,
        (t) => fillAndTap(t, {}, 'Sair de todos os aparelhos'),
      ),
    };

Future<Harness> openSessions(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (read, write, then) = sessionsStates[name]!;
  final h = Harness(
    signedIn: true,
    api: (req) => req.method == 'GET' && req.url.path == '/v1/sessions'
        ? read()
        : write?.call() ?? http.Response('', 204),
  )..family = ownerFamily;
  await h.pump(
    tester,
    initial: '/conta/aparelhos',
    size: size,
    textScale: textScale,
  );
  await then?.call(tester);
  return h;
}

/// The data screen in its key states: what the export answers (the
/// document when null), whether the share sheet takes the file, and
/// whether to choose "Baixar meus dados".
final dataStates = <String, (http.Response Function()?, bool, bool)>{
  'data': (null, true, false),
  'data, done': (null, true, true),
  'data, sheet dismissed': (null, false, true),
  'data, rate limited': (
    () => problem(429, 'rate_limited', headers: {'retry-after': '90'}),
    true,
    true,
  ),
  'data, failed': (() => problem(503, 'unavailable'), true, true),
};

Future<Harness> openData(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (answer, handed, choose) = dataStates[name]!;
  final h = Harness(
    signedIn: true,
    exports: PlatformExportDelivery(
      web: false,
      share: (_, {origin}) async => handed,
    ),
    api: (req) => switch (req.url.path) {
      '/v1/sessions' => json(200, {'sessions': <Object>[]}),
      _ => answer?.call() ?? json(200, {'format': 'telinhasegura.export/1'}),
    },
  )..family = ownerFamily;
  await h.pump(
    tester,
    initial: '/conta/dados',
    size: size,
    textScale: textScale,
  );
  if (choose) await fillAndTap(tester, {}, 'Baixar meus dados');
  return h;
}

/// Taps [text] if it shows (an action only one width offers).
Future<void> tapIfShown(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) return;
  await tapOn(tester, find.text(text).last);
}

/// Through the enrollment's key step to its code step.
Future<void> toCodeStep(WidgetTester tester) =>
    tapOn(tester, find.text('Já adicionei'));

/// Through the code step to the recovery codes.
Future<void> toRecoveryCodes(WidgetTester tester) async {
  await toCodeStep(tester);
  await tester.enterText(find.byType(TextField), '123456');
  await tester.pumpAndSettle();
  await tapOn(tester, find.text('Confirmar'));
}

/// Status and regeneration as for an admin whose new codes always ask for
/// the elevation, so "Gerar novos códigos" opens the challenge, whose
/// route answers [challenge].
FutureOr<http.Response> Function(http.Request) challengeApi({
  FutureOr<http.Response> Function(http.Request)? challenge,
}) => mfaApi(
  challenge: challenge,
  regenerate: () => problem(403, 'elevation_required'),
);

/// From the status, through the confirmation, to the challenge.
Future<void> toChallenge(WidgetTester tester) async {
  await tapOn(tester, find.text('Gerar novos códigos'));
  await tapOn(tester, find.text('Gerar novos códigos').last);
}

/// The challenge with a code sent.
Future<void> challengeWith(WidgetTester tester) async {
  await toChallenge(tester);
  await tester.enterText(find.byType(TextField).last, '123456');
  await tapOn(tester, find.text('Confirmar').last);
}

/// The second factor's screens in their key states:
/// the route, the API and what to do once there.
final mfaStates =
    <
      String,
      (
        String,
        FutureOr<http.Response> Function(http.Request),
        Future<void> Function(WidgetTester)?,
      )
    >{
      'sua conta, role holder': ('/conta', mfaApi(), null),
      'verification, not enrolled': (
        '/conta/verificacao',
        mfaApi(status: () => json(200, mfaStatusJson(enrolled: false))),
        null,
      ),
      'verification, enrolled, few codes': (
        '/conta/verificacao',
        mfaApi(status: () => json(200, mfaStatusJson(codesLeft: 2))),
        null,
      ),
      'verification, new codes confirmation': (
        '/conta/verificacao',
        mfaApi(),
        (t) => tapOn(t, find.text('Gerar novos códigos')),
      ),
      'verification, new codes': (
        '/conta/verificacao',
        mfaApi(),
        (t) async {
          await tapOn(t, find.text('Gerar novos códigos'));
          await tapOn(t, find.text('Gerar novos códigos').last);
        },
      ),
      'enrollment, key': ('/conta/verificacao/ativar', mfaApi(), null),
      'enrollment, key with the QR': (
        '/conta/verificacao/ativar',
        mfaApi(),
        (t) => tapIfShown(t, 'Mostrar QR code'),
      ),
      'enrollment, code': ('/conta/verificacao/ativar', mfaApi(), toCodeStep),
      'enrollment, code refused': (
        '/conta/verificacao/ativar',
        mfaApi(confirm: (_) => problem(422, 'mfa_code_invalid')),
        toRecoveryCodes,
      ),
      'enrollment, blocked': (
        '/conta/verificacao/ativar',
        mfaApi(
          confirm: (_) =>
              problem(429, 'rate_limited', headers: {'retry-after': '240'}),
        ),
        toRecoveryCodes,
      ),
      'enrollment, recovery codes': (
        '/conta/verificacao/ativar',
        mfaApi(),
        toRecoveryCodes,
      ),
      'challenge, code': ('/conta/verificacao', challengeApi(), toChallenge),
      'challenge, recovery code': (
        '/conta/verificacao',
        challengeApi(),
        (t) async {
          await toChallenge(t);
          await tapOn(t, find.text('Usar um código de recuperação'));
        },
      ),
      'challenge, code refused': (
        '/conta/verificacao',
        challengeApi(challenge: (_) => problem(400, 'mfa_code_invalid')),
        challengeWith,
      ),
      'challenge, blocked': (
        '/conta/verificacao',
        challengeApi(
          challenge: (_) => problem(429, 'rate_limited', retryAfterBody: 240),
        ),
        challengeWith,
      ),
      'challenge, offline': (
        '/conta/verificacao',
        challengeApi(challenge: (_) => throw http.ClientException('offline')),
        challengeWith,
      ),
      'challenge, recovery codes left': (
        '/conta/verificacao',
        challengeApi(challenge: (_) => json(200, elevationJson(left: 2))),
        (t) async {
          await toChallenge(t);
          await tapOn(t, find.text('Usar um código de recuperação'));
          await t.enterText(find.byType(TextField).last, 'ABCDE-FGHJK');
          await tapOn(t, find.text('Confirmar').last);
        },
      ),
      'staff gate, challenge': ('/admin', mfaApi(), null),
      'enrollment, leaving the codes': (
        '/conta/verificacao/ativar',
        mfaApi(),
        (t) async {
          await toRecoveryCodes(t);
          await tapOn(t, find.byTooltip('Voltar').first);
        },
      ),
    };

Future<Harness> openMfa(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (path, api, then) = mfaStates[name]!;
  final h = Harness(signedIn: true, api: api)
    ..family = ownerFamily
    ..roles = ['admin'];
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  await then?.call(tester);
  return h;
}

/// The account deletion in its key states: Ana's family (none when
/// null), what the deletion answers (204 when null), and whether to
/// declare and choose "Excluir minha conta".
final deleteStates =
    <String, (Map<String, Object?>?, http.Response Function()?, bool)>{
      'delete account, member': (memberFamily, null, false),
      'delete account, no family': (null, null, false),
      'delete account, owner': (ownerFamily, null, false),
      'delete account, owner alone': (ownerAloneFamily, null, false),
      // Only "Excluir a família".
      'delete account, suspended owner alone': (ownerAloneFamily, null, false),
      'delete account, failed': (
        memberFamily,
        () => problem(503, 'unavailable'),
        true,
      ),
      'delete account, rate limited': (
        memberFamily,
        () => problem(429, 'rate_limited', headers: {'retry-after': '90'}),
        true,
      ),
    };

Future<Harness> openDelete(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (family, answer, choose) = deleteStates[name]!;
  final h = Harness(
    signedIn: true,
    api: (req) => switch (req.url.path) {
      '/v1/sessions' => json(200, {'sessions': <Object>[]}),
      _ => answer?.call() ?? http.Response('', 204),
    },
  )..family = family;
  h.email = longEmail;
  if (name.contains('suspended')) h.status = 'suspended';
  await h.pump(
    tester,
    initial: '/conta/excluir',
    size: size,
    textScale: textScale,
  );
  if (choose) {
    final declaration = find.byType(DeclarationRow);
    await tester.ensureVisible(declaration);
    await tester.pumpAndSettle();
    await tester.tap(declaration);
    await tester.pumpAndSettle();
    await fillAndTap(tester, {}, 'Excluir minha conta');
  }
  return h;
}

/// The children's screens, each with its family and what to do once it
/// shows (a step to reach, a confirmation to open).
final childScreens =
    <
      String,
      (String, List<Map<String, Object?>>, Future<void> Function(WidgetTester)?)
    >{
      'children': ('/familia/criancas', [minorJson('m1', 'Lia')], null),
      'children, none': ('/familia/criancas', [], null),
      'children, full': (
        '/familia/criancas',
        [for (var i = 0; i < 10; i++) minorJson('m$i', 'Criança $i')],
        null,
      ),
      'new child, profile': ('/familia/criancas/nova', [], null),
      'new child, consent': ('/familia/criancas/nova', [], toConsent),
      'child': ('/familia/criancas/m1', [minorJson('m1', 'Lia')], null),
      'child, unknown profile': (
        '/familia/criancas/m1',
        [minorJson('m1', 'Lia', avatar: 'dragon', ageBand: '13-16')],
        null,
      ),
      'child, delete confirmation': (
        '/familia/criancas/m1',
        [minorJson('m1', 'Lia')],
        (tester) => tapOn(tester, find.text('Excluir perfil')),
      ),
    };

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Taps near the top of [finder], for a row taller than the viewport (a
/// long address wrapped at large text), whose centre lies off screen.
Future<void> tapTop(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tapAt(tester.getTopLeft(finder) + const Offset(24, 24));
  await tester.pumpAndSettle();
}

/// Fills the first step and continues to the consent.
Future<void> toConsent(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'Nina');
  await tester.pumpAndSettle();
  await tapOn(tester, find.byKey(const ValueKey(Avatar.owl)));
  await tapOn(tester, find.text('9 a 12 anos'));
  await tapOn(tester, find.text('Continuar'));
}

Future<Harness> openChildScreen(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (path, minors, then) = childScreens[name]!;
  final h = Harness(signedIn: true)..family = familyWith(minors);
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  await then?.call(tester);
  return h;
}

/// The adults' screens, the invitations and the deletion, each with its
/// family and what to do once it shows.
final adultScreens =
    <
      String,
      (String, Map<String, Object?>, Future<void> Function(WidgetTester)?)
    >{
      'adults, owner': ('/familia/responsaveis', ownerFamily, null),
      'adults, owner alone': (
        '/familia/responsaveis',
        {
          ...ownerFamily,
          'members': [(ownerFamily['members']! as List).first],
        },
        null,
      ),
      'adults, guardian': ('/familia/responsaveis', guardianFamily, null),
      'adults, guardian actions': (
        '/familia/responsaveis',
        ownerFamily,
        (tester) => tapOn(
          tester,
          find.widgetWithText(DoorRow, addressBreaks('bia@example.com')),
        ),
      ),
      'adults, remove confirmation': (
        '/familia/responsaveis',
        ownerFamily,
        (tester) async {
          await tapOn(
            tester,
            find.widgetWithText(DoorRow, addressBreaks('bia@example.com')),
          );
          await tapOn(tester, find.text('Remover'));
        },
      ),
      'adults, leave confirmation': (
        '/familia/responsaveis',
        guardianFamily,
        (tester) => tapOn(tester, find.text('Sair da família')),
      ),
      'invitations': ('/familia/convites', ownerFamily, null),
      'invitations, none': (
        '/familia/convites',
        {...ownerFamily, 'pending_invitations': 0, 'invitations': <Object>[]},
        null,
      ),
      'invitations, full': (
        '/familia/convites',
        {
          ...ownerFamily,
          'pending_invitations': 4,
          'invitations': [
            for (var i = 0; i < 4; i++)
              {
                'id': 'i$i',
                'email': 'pessoa$i@example.com',
                'expires_at': '2026-10-10T12:00:00Z',
              },
          ],
        },
        null,
      ),
      'delete family': ('/familia/excluir', ownerFamily, null),
      'adults, long email': ('/familia/responsaveis', longFamily, null),
      'adults, long email actions': (
        '/familia/responsaveis',
        longFamily,
        (tester) => tapTop(
          tester,
          find.widgetWithText(DoorRow, addressBreaks(longEmail)),
        ),
      ),
      'adults, long email removal': (
        '/familia/responsaveis',
        longFamily,
        (tester) async {
          await tapTop(
            tester,
            find.widgetWithText(DoorRow, addressBreaks(longEmail)),
          );
          await tapOn(tester, find.text('Remover'));
        },
      ),
      'invitations, long email': ('/familia/convites', longFamily, null),
      'delete family, long email': ('/familia/excluir', longFamily, null),
    };

/// The longest address the wire allows (254 characters, a 64-character
/// local part), which no screen may clip.
final longEmail = '${'a' * 64}@${'b' * 63}.${'c' * 63}.${'d' * 57}.com';

/// The owner's family with [longEmail] as its guardian and its invitation.
final longFamily = <String, Object?>{
  ...ownerFamily,
  'members': [
    (ownerFamily['members']! as List).first,
    {
      ...(ownerFamily['members']! as List<Map<String, Object?>>)[1],
      'email': longEmail,
    },
  ],
  'invitations': [
    {'id': 'i1', 'email': longEmail, 'expires_at': '2026-10-10T12:00:00Z'},
  ],
};

/// Ana as a guardian of bia's family.
final guardianFamily = <String, Object?>{
  ...ownerFamily,
  'role': 'guardian',
  'members': [
    {
      ...(ownerFamily['members']! as List<Map<String, Object?>>)[1],
      'role': 'owner',
    },
    {
      ...(ownerFamily['members']! as List<Map<String, Object?>>)[0],
      'role': 'guardian',
    },
  ],
  'invitations': null,
};

Future<Harness> openAdultScreen(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  assert(longEmail.length == 254);
  final (path, family, then) = adultScreens[name]!;
  final h = Harness(signedIn: true)..family = family;
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  await then?.call(tester);
  return h;
}

/// `/convite` in each state, by what its lookup answers.
final invitationStates = <String, (String, http.Response Function())>{
  'invitation': ('/convite?token=T', () => json(200, invitationPreview())),
  'invitation, long emails': (
    '/convite?token=T',
    () => json(200, invitationPreview(longEmail)),
  ),
  'invitation, no token': ('/convite', () => json(200, invitationPreview())),
  for (final (code, status) in [
    ('invalid_token', 404),
    ('invitation_email_mismatch', 403),
    ('already_in_family', 409),
    ('limit_reached', 409),
    ('unavailable', 503),
  ])
    'invitation, $code': ('/convite?token=T', () => problem(status, code)),
};

Map<String, Object?> invitationPreview([String email = 'bia@example.com']) => {
  'inviter_email': email,
  'invited_email': email,
  'expires_at': '2026-10-10T12:00:00Z',
};

Future<Harness> openInvitation(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (path, lookup) = invitationStates[name]!;
  final h = Harness(signedIn: true, api: (_) => lookup())..family = null;
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  return h;
}

/// Every text holding [longEmail] fits the [width] and shows it whole:
/// wrapped, never clipped or cut short.
void expectWholeAddress(WidgetTester tester, double width) {
  final holding = tester
      .renderObjectList<RenderParagraph>(find.byType(RichText))
      .where(
        (p) => p.text
            .toPlainText()
            .replaceAll(RegExp('[\u200B\u2060]'), '')
            .contains(longEmail),
      );
  expect(holding, isNotEmpty);
  for (final paragraph in holding) {
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.width, lessThanOrEqualTo(width));
  }
}

/// The guardian's kid-mode screens in their states: the path, the family's
/// children, whether it has a PIN, its devices, and the route's `extra`.
final kidModeScreens =
    <String, (String, List<Map<String, Object?>>, bool, int, Object?)>{
      'kid mode guide': (
        '/modo-crianca',
        [minorJson('m1', 'Lia')],
        false,
        0,
        null,
      ),
      'kid mode guide, step 2': (
        '/modo-crianca',
        [minorJson('m1', 'Lia'), minorJson('m2', 'Téo')],
        true,
        0,
        PinSaved.created,
      ),
      'kid mode index': (
        '/modo-crianca',
        [for (var i = 0; i < 10; i++) minorJson('m$i', 'Criança $i')],
        true,
        10,
        null,
      ),
      'kid mode index, no children': ('/modo-crianca', [], true, 2, null),
      'create the PIN': (
        '/modo-crianca/pin',
        [minorJson('m1', 'Lia')],
        false,
        0,
        null,
      ),
      'change the PIN': (
        '/modo-crianca/pin',
        [minorJson('m1', 'Lia')],
        true,
        0,
        null,
      ),
    };

Future<Harness> openKidModeScreen(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (path, minors, pinSet, devices, extra) = kidModeScreens[name]!;
  final h = Harness(signedIn: true)
    ..family = familyWith(minors)
    ..pinSet = pinSet
    ..linkedDevices = [
      for (var i = 0; i < devices; i++) {...deviceJson, 'id': 'd$i'},
    ];
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  if (extra != null) {
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go(path, extra: extra);
    await tester.pumpAndSettle();
  }
  return h;
}

/// A shared kid with two shelves whose plays the server allows.
Harness kidWithShelves() => Harness(
  signedIn: true,
  api: (req) {
    final path = req.url.path;
    if (path == '/v1/child/profile') return json(200, profileJson);
    if (path == '/v1/child/catalog') return json(200, twoShelves);
    if (path.startsWith('/v1/child/thumbs/')) {
      return http.Response.bytes(pixel, 200);
    }
    if (path == '/v1/child/plays') {
      return json(201, {
        'play_id': 'p1',
        'youtube_id': 'yt1',
        'remaining_seconds': 600,
      });
    }
    return http.Response('', 204);
  },
)..kidMode = {'minor_id': 'm1'};

/// A shared kid on a day without time ([state]); an extension answers
/// `over_cap`.
Harness kidAsleep([String state = 'time_up']) => Harness(
  signedIn: true,
  api: (req) {
    final path = req.url.path;
    if (path == '/v1/child/profile') return json(200, profileJson);
    if (path == '/v1/child/catalog') return json(200, shelvesOn(day(state)));
    if (path == '/v1/child/time/extend') return problem(422, 'over_cap');
    return http.Response('', 204);
  },
)..kidMode = {'minor_id': 'm1'};

/// The hand-over, the child side and the PIN gate: each harness, its path,
/// whether it is the child's side (64 dp targets), and what to do
/// once it shows.
final handOverScreens =
    <
      String,
      (Harness Function(), String, bool, Future<void> Function(WidgetTester)?)
    >{
      'hand over': (
        () => Harness(signedIn: true)
          ..family = familyWith([
            minorJson('m1', 'Lia'),
            minorJson('m2', 'Téo'),
          ])
          ..pinSet = true,
        '/modo-crianca/entregar',
        false,
        null,
      ),
      'hand over, chosen': (
        () => Harness(signedIn: true)
          ..family = familyWith([
            for (var i = 0; i < 10; i++) minorJson('m$i', 'Criança $i'),
          ])
          ..pinSet = true,
        '/modo-crianca/entregar',
        false,
        (tester) => tapOn(tester, find.text('Criança 0')),
      ),
      'child home': (
        () => Harness(
          signedIn: true,
          api: (req) => req.url.path == '/v1/child/profile'
              ? json(200, profileJson)
              : http.Response('', 204),
        )..kidMode = {'minor_id': 'm1'},
        '/crianca',
        true,
        null,
      ),
      'child home, no profile': (
        () => Harness(signedIn: true)..kidMode = {'minor_id': null},
        '/crianca',
        true,
        null,
      ),
      // Kid mode: the shelves, a failed catalogue, the player and its
      // error state.
      'child home, shelves': (kidWithShelves, '/crianca', true, null),
      'child home, catalogue failed': (
        () => Harness(
          signedIn: true,
          api: (req) => req.url.path == '/v1/child/catalog'
              ? problem(503, 'internal')
              : http.Response('', 204),
        )..kidMode = {'minor_id': 'm1'},
        '/crianca',
        true,
        null,
      ),
      // Screen time: the sleeping home and the door's time choice.
      'child home, asleep': (kidAsleep, '/crianca', true, null),
      'child home, outside the hours': (
        () => kidAsleep('outside_window'),
        '/crianca',
        true,
        null,
      ),
      'exit gate, more time': (kidAsleep, '/crianca', true, holdExit),
      'exit gate, more time, over the cap': (
        kidAsleep,
        '/crianca',
        true,
        (tester) async {
          await holdExit(tester);
          await tapOn(tester, find.bySemanticsLabel('Mais 60 min'));
          await wrongPin(tester);
          expect(find.text('Hoje já chega a 4 horas, o máximo.'), findsOne);
          // Back to the top, where the adult reads the note and the choice
          // kept, rather than with a row half under the strip.
          await tester.ensureVisible(find.text('PIN dos pais'));
          await tester.pumpAndSettle();
        },
      ),
      'player': (kidWithShelves, '/crianca/assistir/v1', true, null),
      // Pacotinhos: the row, the pacotinho's player, its
      // breath and its goodbye.
      'child home, pacotinhos': (packKid, '/crianca', true, null),
      'pacotinho player': (packKid, '/crianca', true, openPack),
      'pacotinho breath': (
        packKid,
        '/crianca',
        true,
        (tester) async {
          await openPack(tester);
          await endVideo(tester);
        },
      ),
      'pacotinho goodbye': (
        packKid,
        '/crianca',
        true,
        (tester) async {
          await openPack(tester);
          for (var i = 0; i < 2; i++) {
            await endVideo(tester);
            await tapOn(tester, find.byType(PackBreath));
          }
          await endVideo(tester);
        },
      ),
      'player, failed': (
        kidWithShelves,
        '/crianca/assistir/v1',
        true,
        (tester) async {
          final services = AppScope.of(
            tester.element(find.byType(PlayerScreen)),
          );
          (services.player as FakeKidPlayer).current!.emit(
            const PlayerFailed(),
          );
          await tester.pump();
          await tester.pump();
        },
      ),
      'exit gate': (
        () =>
            Harness(signedIn: true, api: (_) => problem(403, 'invalid_pin'))
              ..kidMode = {'minor_id': 'm1'},
        '/crianca/sair',
        true,
        null,
      ),
      'exit gate, wrong PIN': (
        () =>
            Harness(signedIn: true, api: (_) => problem(403, 'invalid_pin'))
              ..kidMode = {'minor_id': 'm1'},
        '/crianca/sair',
        true,
        wrongPin,
      ),
      'link code, choose': (linkFamily, '/modo-crianca/vincular', false, null),
      'link code, live': (
        linkFamily,
        '/modo-crianca/vincular',
        false,
        generate,
      ),
      'link code, expired': (
        linkFamily,
        '/modo-crianca/vincular',
        false,
        (tester) async {
          await generate(tester);
          await tester.pump(const Duration(minutes: 10));
          await tester.pumpAndSettle();
        },
      ),
      for (final n in [0, 2, 10])
        'devices, $n': (
          () => devicesFamily(n),
          '/modo-crianca/aparelhos',
          false,
          null,
        ),
      'unlink confirmation': (
        () => devicesFamily(2),
        '/modo-crianca/aparelhos',
        false,
        (tester) async {
          // The label, not the action's centre: QuietAction spans the row
          // and holds its target at the start.
          await tapOn(tester, find.text('Desvincular').first);
          expect(find.textContaining('Desvincular Tablet'), findsOneWidget);
        },
      ),
      'PIN gate': (
        () => Harness(signedIn: true, kidModeMark: MemoryKidModeMark({'a'})),
        '/pin',
        false,
        null,
      ),
      'PIN gate, wrong PIN': (
        () => Harness(
          signedIn: true,
          kidModeMark: MemoryKidModeMark({'a'}),
          api: (_) => problem(403, 'invalid_pin'),
        ),
        '/pin',
        false,
        wrongPin,
      ),
      'redeem': (redeemDevice, '/vincular-aparelho', false, null),
      'redeem, prefilled': (
        redeemDevice,
        '/vincular-aparelho?codigo=abcd1234',
        false,
        null,
      ),
      'redeem, refused': (redeemDevice, '/vincular-aparelho', false, redeemNow),
      'profile picker': (
        () => Harness(
          kind: ClientKind.mobile,
          devices: MemoryDeviceCredentialStore('dev'),
          api: (req) => req.url.path == '/v1/child/profiles'
              ? json(200, {
                  'profiles': [
                    for (var i = 0; i < 10; i++)
                      {...profileJson, 'id': 'm$i', 'nickname': 'Criança $i'},
                  ],
                })
              : json(200, profileJson),
        ),
        '/crianca/sair',
        true,
        (tester) async {
          await wrongPin(tester);
          expect(find.text('Quem vai assistir?'), findsOneWidget);
        },
      ),
    };

/// A child's phone, unlinked, whose redemption is refused.
Harness redeemDevice() => Harness(
  kind: ClientKind.mobile,
  devices: MemoryDeviceCredentialStore(),
  api: (_) => problem(400, 'invalid_token'),
);

/// Fills the code and the name and presses "Vincular".
Future<void> redeemNow(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Código'), 'ABCD1234');
  await tester.enterText(
    find.widgetWithText(TextField, 'Nome do aparelho'),
    'Tablet grande da sala de estar da vó Bia',
  );
  await tester.pumpAndSettle();
  await tapOn(tester, find.widgetWithText(FilledButton, 'Vincular'));
  expect(find.byType(ErrorNote), findsOneWidget);
}

/// Lia and Téo's family, whose link codes answer a live code.
Harness linkFamily() =>
    Harness(
        signedIn: true,
        api: (req) => req.url.path == '/v1/parental/link-codes'
            ? liveCode(req)
            : http.Response('', 204),
      )
      ..family = familyWith([minorJson('m1', 'Lia'), minorJson('m2', 'Téo')])
      ..pinSet = true;

/// Chooses Lia and generates her code.
Future<void> generate(WidgetTester tester) async {
  await tapOn(tester, find.text('Lia'));
  await tapOn(tester, find.text('Gerar código'));
  expect(find.bySemanticsLabel(RegExp('^Código: ')), findsOneWidget);
}

/// Lia and Téo's family with [n] linked devices, the first named with
/// the longest label (40 characters), the last of an unknown child.
Harness devicesFamily(int n) => Harness(signedIn: true)
  ..family = familyWith([minorJson('m1', 'Lia'), minorJson('m2', 'Téo')])
  ..pinSet = true
  ..linkedDevices = [
    for (var i = 0; i < n; i++)
      device(
        'd$i',
        i == 0 ? 'Tablet grande da sala de estar da vó Bia' : 'Celular $i',
        i == n - 1 ? 'gone' : 'm${i % 2 + 1}',
        daysAgo: i,
      ),
  ];

/// Types a PIN the server refuses.
Future<void> wrongPin(WidgetTester tester) async {
  for (final d in '1111'.split('')) {
    await tapOn(tester, find.bySemanticsLabel(d));
  }
  await tapOn(tester, find.bySemanticsLabel('Confirmar'));
}

/// Taps the day's first pacotinho on the child home.
Future<void> openPack(WidgetTester tester) =>
    tapOn(tester, find.byType(PackTile).first);

/// Ends the video the pacotinho's player plays.
Future<void> endVideo(WidgetTester tester) async {
  final services = AppScope.of(tester.element(find.byType(PackPlayerScreen)));
  (services.player as FakeKidPlayer).current!.emit(const PlayerEnded());
  await tester.pumpAndSettle();
}

Future<Harness> openHandOverScreen(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (build, path, _, then) = handOverScreens[name]!;
  final h = build();
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  await then?.call(tester);
  return h;
}

/// The screen-time screens in their states: the path, the API, and what
/// to do once the screen shows.
final screenTimeScreens =
    <
      String,
      (
        String,
        FutureOr<http.Response> Function(http.Request),
        Future<void> Function(WidgetTester)?,
      )
    >{
      'screen time list': (
        '/familia/tempo',
        screenTimeApi(
          rules: {
            'm1': () => json(200, rulesJson(state: 'time_up')),
            'm2': () => problem(503, 'unavailable'),
          },
        ),
        null,
      ),
      'screen time hub': (
        '/familia/tempo/m1',
        screenTimeApi(
          rules: {
            'm1': () => json(200, rulesJson(isDefault: true, extension: 30)),
          },
          usage: () => json(200, usageJson([45, 70, 299, 0, 15, 60, 1])),
        ),
        null,
      ),
      'screen time hub, read failed': (
        '/familia/tempo/m1',
        screenTimeApi(rules: {'m1': () => problem(503, 'unavailable')}),
        null,
      ),
      'more time': ('/familia/tempo/m1/mais', screenTimeApi(), null),
      'more time, over cap': (
        '/familia/tempo/m1/mais',
        screenTimeApi(extend: (_) => problem(409, 'over_cap')),
        (tester) async {
          await choose(tester, '60 min');
          await give(tester);
        },
      ),
      'more time, done': (
        '/familia/tempo/m1/mais',
        screenTimeApi(),
        (tester) async {
          await choose(tester, '30 min');
          await give(tester);
        },
      ),
      'limits': ('/familia/tempo/m1/limite', screenTimeApi(), null),
      'limits, out of order': (
        '/familia/tempo/m1/limite',
        screenTimeApi(),
        (tester) async {
          await pick(tester, 'Começa às 08:00', 20, 0);
          await tapOn(tester, find.text('Salvar'));
        },
      ),
      'limits, done': (
        '/familia/tempo/m1/limite',
        screenTimeApi(),
        (tester) => tapOn(tester, find.text('Salvar')),
      ),
    };

Future<Harness> openScreenTime(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (path, api, then) = screenTimeScreens[name]!;
  final h = Harness(signedIn: true, api: api)
    ..family = familyWith([
      minorJson('m1', 'Lia'),
      minorJson('m2', 'Téo', avatar: 'owl', ageBand: 'ate-4'),
    ]);
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  await then?.call(tester);
  return h;
}

/// The family catalogue screens in their states: the path, the API, and
/// what to do once the screen shows.
final catalogScreens =
    <
      String,
      (
        String,
        FutureOr<http.Response> Function(http.Request),
        Future<void> Function(WidgetTester)?,
      )
    >{
      'catalogue children': ('/familia/videos', catalog.catalogApi(), null),
      'catalogue': ('/familia/videos/m1', catalog.catalogApi(), null),
      'catalogue, long titles, more to read': (
        '/familia/videos/m1',
        catalog.catalogApi(
          catalog: (_, _) => catalog.page([
            catalog.familyItem(
              'v1',
              'Uma história muito comprida sobre um sapo que pulava alto '
                  'demais e chegou até as nuvens do céu',
              channel: 'Um canal de nome também bastante comprido',
              seconds: 3900,
              hidden: true,
            ),
          ], more: true),
        ),
        null,
      ),
      'catalogue, empty': (
        '/familia/videos/m1',
        catalog.catalogApi(catalog: (_, _) => catalog.page([])),
        null,
      ),
      'catalogue, read failed': (
        '/familia/videos/m1',
        catalog.catalogApi(catalog: (_, _) => problem(503, 'unavailable')),
        null,
      ),
      'catalogue, pacotinhos': (
        '/familia/videos/m1',
        catalog.catalogApi(catalog: catalog.withPacks),
        null,
      ),
      'pacotinho': (
        '/familia/videos/m1/pacotinho/k2',
        catalog.catalogApi(catalog: catalog.withPacks),
        null,
      ),
      'pacotinho, long title, five videos': (
        '/familia/videos/m1/pacotinho/k3',
        catalog.catalogApi(
          catalog: (_, _) => catalog.page(
            catalog.liaVideos,
            packs: [
              catalog.packItem(
                'k3',
                'A fazenda do vovô e da vovó no domingo',
                composer: 'cuidador',
                approvals: const {
                  'mae-pai': 1,
                  'cuidador': 1,
                  'pedagogo': 1,
                  'psicologo': 1,
                },
                videos: [
                  for (final i in [1, 2, 3, 4, 5])
                    (
                      'p$i',
                      'Uma história muito comprida sobre um sapo que pulava '
                          'alto demais, parte $i',
                      3900,
                      i.isEven,
                    ),
                ],
              ),
            ],
          ),
        ),
        null,
      ),
      'pacotinho, read failed': (
        '/familia/videos/m1/pacotinho/k2',
        catalog.catalogApi(catalog: (_, _) => problem(503, 'unavailable')),
        null,
      ),
      'family video': ('/familia/videos/m1/v1', catalog.catalogApi(), null),
      'family video, hidden': (
        '/familia/videos/m1/v1',
        catalog.catalogApi(),
        (tester) => tapOn(tester, find.text('Esconder para Lia')),
      ),
      'report': ('/familia/videos/m1/v1/denunciar', catalog.catalogApi(), null),
      'report, chosen, failed': (
        '/familia/videos/m1/v1/denunciar',
        catalog.catalogApi(write: (_) => problem(503, 'unavailable')),
        (tester) async {
          await tapOn(tester, find.text('Assustador'));
          await tapOn(tester, find.widgetWithText(FilledButton, 'Denunciar'));
        },
      ),
      'report, done': (
        '/familia/videos/m1/v1/denunciar',
        catalog.catalogApi(),
        (tester) async {
          await tapOn(tester, find.text('Outro motivo'));
          await tapOn(tester, find.widgetWithText(FilledButton, 'Denunciar'));
        },
      ),
    };

Future<Harness> openCatalog(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (path, api, then) = catalogScreens[name]!;
  final h = Harness(signedIn: true, api: api)..family = catalog.threeChildren;
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  await then?.call(tester);
  return h;
}

/// The suggestion screens in their states: the path, the API, and what
/// to do once the screen shows.
final suggestionScreens =
    <
      String,
      (
        String,
        FutureOr<http.Response> Function(http.Request),
        Future<void> Function(WidgetTester)?,
      )
    >{
      'suggestions': (
        '/sugestoes',
        suggestionApi(
          suggestions: () => json(200, {
            'suggestions': [
              suggestionJson('v1', List.filled(14, 'Bichos').join(' ')),
              suggestionJson('v2', 'Mundo Bita', state: 'held', daysAgo: 3),
              suggestionJson(
                'v3',
                'Galinha Pintadinha',
                channel: 'Canal Galinha Pintadinha Oficial',
                state: 'approved',
                daysAgo: 12,
              ),
            ],
          }),
        ),
        null,
      ),
      'suggestions, none': ('/sugestoes', suggestionApi(), null),
      'suggestions, read failed': (
        '/sugestoes',
        suggestionApi(suggestions: () => problem(503, 'unavailable')),
        null,
      ),
      'suggest': ('/sugestoes/nova', suggestionApi(), null),
      'suggest, refused': (
        '/sugestoes/nova',
        suggestionApi(
          suggest: (_) =>
              problem(422, 'video_refused', extra: {'reason': 'not_for_kids'}),
        ),
        send,
      ),
      'suggest, YouTube unavailable': (
        '/sugestoes/nova',
        suggestionApi(suggest: (_) => problem(503, 'video_source_unavailable')),
        send,
      ),
      'suggest, done': (
        '/sugestoes/nova',
        suggestionApi(suggest: (_) => json(200, videoJson)),
        send,
      ),
    };

Future<Harness> openSuggestions(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (path, api, then) = suggestionScreens[name]!;
  final h = Harness(signedIn: true, api: api)..family = ownerFamily;
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  await then?.call(tester);
  return h;
}

/// The curator's screens in their states: the path, the API, and what
/// to do once the screen shows.
final curatorScreens =
    <
      String,
      (
        String,
        FutureOr<http.Response> Function(http.Request),
        Future<void> Function(WidgetTester, Harness)?,
      )
    >{
      'queue': (
        '/curadoria',
        curatorApi(
          queue: (_) => queuePage([
            queuedJson('v1', List.filled(14, 'Bichos').join(' ')),
            queuedJson(
              'v2',
              'Galinha Pintadinha',
              channel: 'Canal Galinha Pintadinha Oficial',
              seconds: 3900,
              revisit: true,
            ),
          ], next: 50),
        ),
        null,
      ),
      'queue, empty': ('/curadoria', curatorApi(), null),
      'queue, read failed': (
        '/curadoria',
        curatorApi(queue: (_) => problem(503, 'unavailable')),
        null,
      ),
      'review': (
        '/curadoria/v1',
        curatorApi(
          video: (_) => detailOf(
            {
              ...queuedJson('v1', List.filled(14, 'Bichos').join(' ')),
              'round': 3,
            },
            reviews: [
              reviewJson,
              {...rejectionJson, 'reason': List.filled(40, 'susto').join(' ')},
            ],
          ),
        ),
        null,
      ),
      'review, none yet': ('/curadoria/v1', curatorApi(), null),
      'review, player failed': (
        '/curadoria/v1',
        curatorApi(),
        (tester, h) async {
          h.adultPlayer.current!.emit(const PlayerFailed());
          await tester.pumpAndSettle();
        },
      ),
      'approve': ('/curadoria/v1/aprovar', curatorApi(), null),
      'approve, refused': (
        '/curadoria/v1/aprovar',
        curatorApi(review: (_) => problem(422, 'validation')),
        (tester, _) => approve(tester),
      ),
      'approve, done': (
        '/curadoria/v1/aprovar',
        curatorApi(),
        (tester, _) => approve(tester),
      ),
      'refuse': ('/curadoria/v1/recusar', curatorApi(), null),
      'refuse, near the bound': (
        '/curadoria/v1/recusar',
        curatorApi(review: (_) => problem(422, 'validation')),
        (tester, _) => refuse(tester, reason: 'a' * 480),
      ),
      'refuse, done': (
        '/curadoria/v1/recusar',
        curatorApi(),
        (tester, _) => refuse(tester),
      ),
      // The pacotinhos.
      'pacotinhos': (
        '/pacotinhos',
        packApi(
          list: (_) => packPage([
            packOf(
              'p1',
              List.filled(5, 'Bichos').join(' '),
              theme: 'natureza',
              reviewable: true,
            ),
            packOf('p2', 'Hora do banho', state: 'approved'),
          ], hasMore: true),
        ),
        null,
      ),
      'pacotinhos, empty': ('/pacotinhos', packApi(), null),
      'compose, empty': ('/pacotinhos/novo', packApi(videos: _bichos), null),
      'compose, five picked': (
        '/pacotinhos/novo',
        packApi(videos: _bichos),
        (tester, _) => composing.pick(tester, [
          'Abelha',
          'Baleia',
          'Coelho',
          'Dromedário',
          'Elefante',
        ]),
      ),
      'compose, over the limit': (
        '/pacotinhos/novo',
        packApi(
          videos: (_) => composing.approvedOf('bichos', [
            'Abelha',
            'Baleia',
            'Coelho',
          ], seconds: 480),
        ),
        (tester, _) => composing.pick(tester, ['Abelha', 'Baleia', 'Coelho']),
      ),
      'picker, a theme open': (
        '/pacotinhos/novo',
        packApi(videos: _bichos),
        (tester, _) async {
          await tapOn(tester, find.text('Adicionar vídeos'));
          await tapOn(tester, find.widgetWithText(SelectableRow, 'Bichos'));
        },
      ),
      'recompose': ('/pacotinhos/p1/mudar', packApi(), null),
      'pack review': (
        '/pacotinhos/p1',
        packApi(
          pack: (id) => json(
            200,
            packOf(
              id,
              'Hora do banho',
              state: 'approved',
              round: 3,
              reviewable: true,
              composer: 'psicologo',
              videos: [
                packVideoJson(
                  'v1',
                  List.filled(12, 'Galinha').join(' '),
                  channel: 'Canal Galinha Pintadinha Oficial',
                ),
                packVideoJson('v2', 'Sapo Cururu', state: 'held'),
                packVideoJson('v3', 'Pato Pateta', seconds: 3900),
              ],
              reviews: [
                {
                  'display_role': 'cuidador',
                  'decision': 'reject',
                  'reason': List.filled(30, 'longo').join(' '),
                  'reviewed_at': '2026-10-06T12:00:00Z',
                },
              ],
            ),
          ),
        ),
        null,
      ),
      'pack video': ('/pacotinhos/p1/videos/v2', packApi(), null),
      'pack approve': ('/pacotinhos/p1/aprovar', packApi(), null),
      'pack refuse': ('/pacotinhos/p1/recusar', packApi(), null),
    };

FutureOr<http.Response> _bichos(http.Request req) => composing.approvedOf(
  'bichos',
  ['Abelha', 'Baleia', 'Coelho', 'Dromedário', 'Elefante', 'Foca'],
  next: 6,
);

/// The admin's routes with the pacotinhos'.
FutureOr<http.Response> Function(http.Request) _adminPacks({
  FutureOr<http.Response> Function(String id)? pack,
}) {
  final packs = packApi(
    list: (_) => packPage([
      packOf('p1', 'Hora do banho', state: 'approved'),
      packOf('p2', List.filled(6, 'Natureza').join(' '), state: 'held'),
    ], hasMore: true),
    pack: pack,
  );
  return (req) =>
      req.url.path.contains('/packs') ? packs(req) : adminApi()(req);
}

Future<Harness> openCurator(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (path, api, then) = curatorScreens[name]!;
  final h = Harness(signedIn: true, api: api)
    ..family = ownerFamily
    ..roles = ['curator'];
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  await then?.call(tester, h);
  return h;
}

/// The admin's screens in their states: the path, the API, and what to
/// do once the screen shows.
final adminScreens =
    <
      String,
      (
        String,
        FutureOr<http.Response> Function(http.Request),
        Future<void> Function(WidgetTester, Harness)?,
      )
    >{
      'administration': (
        '/admin',
        adminApi(
          staff: () => staffList([
            for (var i = 0; i < 6; i++)
              memberOf('a$i', 'c$i@example.com', [curatorRole()]),
          ]),
          held: () => heldList([longHeld]),
        ),
        null,
      ),
      // The team.
      'team': (
        '/admin/equipe',
        adminApi(
          staff: () => staffList([
            selfMember,
            memberOf('a1', longEmail, [
              curatorRole(role: 'psicologo'),
              moderatorRole(),
            ]),
            memberOf('a2', 'bia@example.com', [
              curatorRole(role: 'mae-pai', verified: false),
            ]),
            memberOf('a3', 'caio@example.com', [moderatorRole()]),
          ]),
        ),
        null,
      ),
      'team, read failed': (
        '/admin/equipe',
        adminApi(staff: () => problem(503, 'unavailable')),
        null,
      ),
      'appoint someone': ('/admin/equipe/nova', adminApi(), null),
      'appoint someone, curation, professional': (
        '/admin/equipe/nova',
        adminApi(),
        (tester, _) =>
            staffing.fill(tester, email: longEmail, role: 'Pediatra'),
      ),
      'appoint someone, confirming': (
        '/admin/equipe/nova',
        adminApi(),
        (tester, _) async {
          await staffing.fill(tester, email: longEmail, papel: 'Moderação');
          await tapOn(tester, staffing.proceed);
        },
      ),
      'appoint someone, refused on the field': (
        '/admin/equipe/nova',
        adminApi(grant: (_) => problem(409, 'email_unverified')),
        (tester, _) => staffing.appoint(tester, papel: 'Moderação'),
      ),
      'appoint someone, done': (
        '/admin/equipe/nova',
        adminApi(
          grant: (_) => json(201, memberOf('a9', longEmail, [moderatorRole()])),
        ),
        (tester, _) => staffing.appoint(tester, papel: 'Moderação'),
      ),
      'member, every role': (
        '/admin/equipe/a1',
        adminApi(
          staff: () => staffList([
            memberOf('a1', longEmail, [
              adminRole(),
              curatorRole(),
              moderatorRole(),
            ]),
          ]),
        ),
        null,
      ),
      'member, a curator': (
        '/admin/equipe/a1',
        adminApi(
          staff: () => staffList([
            memberOf('a1', longEmail, [curatorRole()]),
          ]),
        ),
        null,
      ),
      'member, own sheet': (
        '/admin/equipe/a',
        adminApi(
          staff: () => staffList([
            memberOf('a', longEmail, [adminRole(), curatorRole()]),
          ]),
        ),
        null,
      ),
      'member, saved': (
        '/admin/equipe/a1',
        adminApi(
          staff: () => staffList([
            memberOf('a1', longEmail, [curatorRole()]),
          ]),
          revise: (_) => json(
            200,
            memberOf('a1', longEmail, [curatorRole(role: 'educador')]),
          ),
        ),
        (tester, _) async {
          await tapOn(tester, find.text('Educador(a)'));
          await tapOn(tester, find.byType(DeclarationRow));
          await tapOn(tester, find.text('Salvar alterações'));
          await staffing.confirmWith(tester, 'Salvar alterações');
        },
      ),
      'member, confirming the removal': (
        '/admin/equipe/a1',
        adminApi(
          staff: () => staffList([
            memberOf('a1', longEmail, [moderatorRole()]),
          ]),
        ),
        (tester, _) => tapOn(tester, find.text('Tirar da moderação')),
      ),
      'held': (
        '/moderacao/retidos',
        adminApi(
          held: () => heldList([
            longHeld,
            heldOf(queuedJson('v2', 'Patati'), reason: 'unavailable'),
          ]),
        ),
        null,
      ),
      // The numbers failed, the doors still there.
      'administration, numbers failed': (
        '/admin',
        adminApi(metrics: () => problem(503, 'unavailable')),
        null,
      ),
      // The staff audit log at its bounds, with a page to come.
      'auditoria': (
        '/admin/auditoria',
        adminApi(
          audit: (_) => auditPage([
            for (final (event, subject) in [
              ('account_sessions_revoked', 'account'),
              ('video_removed', 'video'),
              ('mfa_reset', null),
            ])
              {
                'id': 1,
                'occurred_at': '2026-10-08T12:00:00Z',
                'event': event,
                'actor_id': 'a1',
                'actor_email': longEmail,
                'actor_role': 'admin',
                'subject_kind': subject,
                'subject_id': subject == null ? null : 's1',
                'subject_email_masked': subject == 'account'
                    ? 'p•••@g•••.com'
                    : null,
                'reason': List.filled(40, 'motivo').join(' ').substring(0, 200),
                'metadata': {'sessions': '12'},
              },
          ], next: 50),
        ),
        null,
      ),
      'auditoria, read failed': (
        '/admin/auditoria',
        adminApi(audit: (_) => problem(503, 'unavailable')),
        null,
      ),
      // The account search, filled near the reason's bound, refused on the
      // field and blocked for the hour.
      'account search': ('/admin/contas', adminApi(), null),
      'account search, filled': (
        '/admin/contas',
        adminApi(),
        (tester, _) => directory.fill(
          tester,
          who: longEmail,
          motivo: List.filled(40, 'motivo').join(' ').substring(0, 190),
        ),
      ),
      'account search, not found': (
        '/admin/contas',
        adminApi(lookup: (_) => problem(404, 'account_not_found')),
        _searched,
      ),
      'account search, blocked': (
        '/admin/contas',
        adminApi(
          lookup: (_) => problem(429, 'rate_limited', retryAfterBody: 3600),
        ),
        _searched,
      ),
      // The sheet at its bounds: every way in, every role, 20 actions, a
      // handful of devices and sessions.
      'account sheet': (
        '/admin/contas',
        adminApi(lookup: (_) => json(200, longSheet)),
        _searched,
      ),
      'account sheet, no family': (
        '/admin/contas',
        adminApi(
          lookup: (_) => json(200, {
            ...sheetJson,
            'roles': <Object>[],
            'family': null,
            'devices': <Object>[],
            'sessions': <Object>[],
            'actions': <Object>[],
          }),
        ),
        _searched,
      ),
      'account sheet, own': (
        '/admin/contas',
        adminApi(lookup: (_) => json(200, {...longSheet, 'account_id': 'a'})),
        _searched,
      ),
      'account sheet, done': (
        '/admin/contas',
        adminApi(lookup: (_) => json(200, longSheet)),
        (tester, h) async {
          await _searched(tester, h);
          await tapOn(tester, find.text('Desvincular').first);
          await tester.enterText(
            find.widgetWithText(TextField, 'Motivo'),
            'Pedido da família.',
          );
          await tester.pump();
          await tapOn(tester, find.widgetWithText(FilledButton, 'Desvincular'));
        },
      ),
      'account sheet, confirming the reset': (
        '/admin/contas',
        adminApi(lookup: (_) => json(200, longSheet)),
        (tester, h) async {
          await _searched(tester, h);
          await tapOn(tester, find.text('Enviar redefinição de senha'));
        },
      ),
      // The standing at its bounds, and the suspension's confirmation
      // with every role it takes away.
      'account sheet, suspended': (
        '/admin/contas',
        adminApi(lookup: (_) => json(200, longSuspended)),
        _searched,
      ),
      'account sheet, confirming the suspension': (
        '/admin/contas',
        adminApi(
          lookup: (_) => json(200, {
            ...longSheet,
            'roles': ['curator', 'moderator'],
          }),
        ),
        (tester, h) async {
          await _searched(tester, h);
          await tapOn(tester, find.text('Suspender conta'));
        },
      ),
      'account sheet, suspended done': (
        '/admin/contas',
        adminApi(
          lookup: (_) => json(200, {
            ...longSheet,
            'roles': ['curator'],
          }),
          support: (_) => json(200, longSuspended),
        ),
        (tester, h) async {
          await _searched(tester, h);
          await _confirmStaff(tester, 'Suspender conta');
        },
      ),
      'account sheet, reinstatement refused': (
        '/admin/contas',
        adminApi(
          lookup: (_) => json(200, longSuspended),
          support: (_) => problem(409, 'not_suspended'),
        ),
        (tester, h) async {
          await _searched(tester, h);
          await _confirmStaff(tester, 'Reativar conta');
        },
      ),
      'held, none': ('/moderacao/retidos', adminApi(), null),
      'held, read failed': (
        '/moderacao/retidos',
        adminApi(held: () => problem(503, 'unavailable')),
        null,
      ),
      'held video': (
        '/moderacao/retidos/v1',
        adminApi(held: () => heldList([longHeld])),
        null,
      ),
      'held video, player failed': (
        '/moderacao/retidos/v1',
        adminApi(held: () => heldList([longHeld])),
        (tester, h) async {
          h.adultPlayer.current!.emit(const PlayerFailed());
          await tester.pumpAndSettle();
        },
      ),
      'held video, confirming the removal': (
        '/moderacao/retidos/v1',
        adminApi(held: () => heldList([longHeld])),
        (tester, _) => tapOn(tester, find.text('Remover de vez')),
      ),
      // The confirmation's reason near its bound.
      'held video, confirming the reopen with a reason': (
        '/moderacao/retidos/v1',
        adminApi(held: () => heldList([longHeld])),
        (tester, _) async {
          await tapOn(tester, find.text('Reabrir para revisão'));
          await tester.enterText(
            find.widgetWithText(TextField, 'Motivo'),
            List.filled(40, 'canal').join(' ').substring(0, 190),
          );
          await tester.pumpAndSettle();
        },
      ),
      // The pacotinhos.
      'admin pacotinhos': ('/admin/pacotinhos', _adminPacks(), null),
      'admin pacotinho': (
        '/admin/pacotinhos/p1',
        _adminPacks(
          pack: (id) => json(
            200,
            packOf(
              id,
              List.filled(6, 'Hora do banho').join(' '),
              state: 'approved',
              composer: 'pediatra',
              provenance: {
                'approvals': {'mae-pai': 2, 'psicologo': 1},
                'last_reviewed_at': '2026-10-05T12:00:00Z',
              },
            ),
          ),
        ),
        null,
      ),
      'admin pacotinho, confirming the removal': (
        '/admin/pacotinhos/p1',
        _adminPacks(),
        (tester, _) => tapOn(tester, find.text('Remover de vez')),
      ),
    };

/// The account search with a lookup sent.
Future<void> _searched(WidgetTester tester, Harness _) async {
  await directory.fill(tester);
  await directory.press(tester);
}

/// Opens the sheet's [action], gives a reason, and confirms.
Future<void> _confirmStaff(WidgetTester tester, String action) async {
  await tapOn(tester, find.text(action));
  await tester.enterText(
    find.widgetWithText(TextField, 'Motivo'),
    'Pedido da família.',
  );
  await tester.pump();
  await tapOn(tester, find.widgetWithText(FilledButton, action));
}

/// [longSheet] suspended, with a reason of 200 characters.
final longSuspended = <String, Object?>{
  ...longSheet,
  'roles': <Object>[],
  'sessions': <Object>[],
  'suspension': {
    'since': '2025-12-31T23:59:00Z',
    'reason': List.filled(40, 'motivo').join(' ').substring(0, 200),
  },
};

/// An account sheet at its bounds: a long masked address, every way in
/// and every role, four devices and sessions, 20 actions with reasons of
/// 200 characters.
final longSheet = <String, Object?>{
  ...sheetJson,
  'email_masked': 'p•••@g•••.${'c' * 40}.com',
  'providers': ['password', 'google', 'apple'],
  'roles': ['curator', 'moderator', 'admin'],
  'family': {'role': 'guardian', 'minors': 12, 'devices': 1240},
  'devices': [
    for (var i = 0; i < 4; i++)
      {
        'id': 'd$i',
        'linked_at': '2025-12-31T23:59:00Z',
        'last_seen_at': '2026-10-01T12:00:00Z',
      },
  ],
  'sessions': [
    for (final client in ['web', 'mobile', 'web', 'mobile'])
      {
        'client': client,
        'created_at': '2025-12-31T23:59:00Z',
        'last_seen_at': '2026-10-01T12:00:00Z',
      },
  ],
  'actions': [
    for (var i = 0; i < 20; i++)
      {
        ...actionJson,
        'id': i,
        'event': i.isEven ? 'account_password_reset_sent' : 'mfa_reset',
        'actor_email': longEmail,
        'reason': List.filled(40, 'motivo').join(' ').substring(0, 200),
      },
  ],
};

/// A held video at its bounds: a 100-character title, a 500-character
/// refusal and note, every report reason.
final longHeld = heldOf(
  queuedJson('v1', List.filled(15, 'Bichos').join(' ').substring(0, 100)),
  rejections: [
    {...rejectionJson, 'reason': List.filled(83, 'susto').join(' ')},
    {...rejectionJson, 'display_role': 'pediatra'},
  ],
  reason: 'reports',
  reports: {'inadequado': 3, 'assustador': 12, 'publicidade': 1, 'outro': 2},
  notes: [List.filled(83, 'chorou').join(' ').substring(0, 500)],
);

Future<Harness> openAdmin(
  WidgetTester tester,
  String name, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final (path, api, then) = adminScreens[name]!;
  final h = Harness(signedIn: true, api: api)
    ..family = ownerFamily
    ..roles = ['admin'];
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  await then?.call(tester, h);
  return h;
}

/// The child side's targets: 64 dp, for small hands.
const kidTapTargetGuideline = MinimumTapTargetGuideline(
  size: Size.square(KidSizes.target),
  link: 'kid mode: every target at least KidSizes.target',
);

/// The display title [title] breaks only between words: every word's
/// glyphs share one line, and the title fits the [width] (a title shrinks
/// rather than splitting "Aparelhos" into "Aparelho / s").
void expectWholeWords(WidgetTester tester, String title, double width) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.text(title).first,
      matching: find.byType(RichText),
    ),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.size.width, lessThanOrEqualTo(width));
  var start = 0;
  for (final word in title.split(' ')) {
    final lines = {
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      ))
        box.top,
    };
    expect(lines, hasLength(1), reason: '"$word" breaks inside "$title"');
    start += word.length + 1;
  }
}

/// Every account screen's title and the family's longest single words,
/// each with how to open it.
final longTitles =
    <String, Future<Harness> Function(WidgetTester, Size, double)>{
      'Sua conta': (t, size, scale) =>
          openAccount(t, 'account', size: size, textScale: scale),
      'Trocar o e-\u2060mail': (t, size, scale) =>
          openAccountTask(t, 'change email', size: size, textScale: scale),
      'Trocar a senha': (t, size, scale) =>
          openAccountTask(t, 'password', size: size, textScale: scale),
      'Aparelhos conectados': (t, size, scale) =>
          openSessions(t, 'sessions', size: size, textScale: scale),
      'Seus dados': (t, size, scale) =>
          openData(t, 'data', size: size, textScale: scale),
      'Excluir conta': (t, size, scale) =>
          openDelete(t, 'delete account, member', size: size, textScale: scale),
      'Verificação em duas etapas': (t, size, scale) => openMfa(
        t,
        'verification, not enrolled',
        size: size,
        textScale: scale,
      ),
      'Conecte o app autenticador': (t, size, scale) =>
          openMfa(t, 'enrollment, key', size: size, textScale: scale),
      'Digite o código que o app mostra': (t, size, scale) =>
          openMfa(t, 'enrollment, code', size: size, textScale: scale),
      'Código do app autenticador': (t, size, scale) =>
          openMfa(t, 'challenge, code', size: size, textScale: scale),
      'Use um código de recuperação': (t, size, scale) =>
          openMfa(t, 'challenge, recovery code', size: size, textScale: scale),
      'Guarde seus códigos de recuperação': (t, size, scale) => openMfa(
        t,
        'enrollment, recovery codes',
        size: size,
        textScale: scale,
      ),
      'Responsáveis': (t, size, scale) =>
          openAdultScreen(t, 'adults, owner', size: size, textScale: scale),
      'Administração': (t, size, scale) =>
          openAdmin(t, 'administration', size: size, textScale: scale),
      'Vídeos retidos': (t, size, scale) =>
          openAdmin(t, 'held', size: size, textScale: scale),
      'Sugerir um vídeo': (t, size, scale) =>
          openSuggestions(t, 'suggest', size: size, textScale: scale),
      'Consentimento': (t, size, scale) => openChildScreen(
        t,
        'new child, consent',
        size: size,
        textScale: scale,
      ),
    };

Future<void> meetsGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  for (final path in routes.keys) {
    testWidgets('$path: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openRoute(tester, path);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$path at 200% text, ${size.width.toInt()} wide: no '
          'overflow, primary action reachable', (tester) async {
        await openRoute(tester, path, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        // The screen's main action: filled, or outlined where the main
        // step happens elsewhere (opening the mail).
        final primary = find.byWidgetPredicate(
          (w) => w is FilledButton || w is OutlinedButton,
        );
        expect(primary, findsWidgets);
        await tester.ensureVisible(primary.first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final state in homes.keys) {
    testWidgets('/ ($state): labelled controls with 48 dp targets', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openHome(tester, state);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('/ ($state) at 200% text, ${size.width.toInt()} wide: no '
          'overflow, every control reachable', (tester) async {
        await openHome(tester, state, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        // The column's first control and its last, "Sair da conta".
        final first = find.byWidgetPredicate(
          (w) => w is DoorRow || w is FilledButton,
        );
        expect(first, findsWidgets);
        for (final control in [
          first.first,
          // A role door with no family.
          if (state.contains('moderator'))
            find.widgetWithText(DoorRow, 'Moderação'),
          find.text('Sair da conta'),
        ]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        if (state.contains('long')) expectWholeAddress(tester, size.width);
      });
    }
  }

  for (final state in accountStates.keys) {
    testWidgets('/conta ($state): labelled controls with 48 dp targets', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openAccount(tester, state);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('/conta ($state) at 200% text, ${size.width.toInt()} wide: '
          'no overflow, every control reachable', (tester) async {
        await openAccount(tester, state, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        // The column's first door and its foot, "Excluir conta".
        for (final control in [
          find.byType(DoorRow).first,
          find.text('Excluir conta'),
        ]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        if (state.contains('long')) expectWholeAddress(tester, size.width);
      });
    }
  }

  for (final name in accountTasks.keys) {
    testWidgets('$name: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openAccountTask(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and last controls reachable', (tester) async {
        await openAccountTask(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        if (name.contains('long')) expectWholeAddress(tester, size.width);
        final first = find.byWidgetPredicate(
          (w) => w is TextField || w is FilledButton,
        );
        // The column's last control: the quiet action or the primary.
        final last = find.byWidgetPredicate(
          (w) => w is ButtonStyleButton && w is! IconButton,
        );
        expect(first, findsWidgets);
        for (final control in [first.first, last.last]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in sessionsStates.keys) {
    testWidgets('$name: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openSessions(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and last controls reachable', (tester) async {
        await openSessions(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        final controls = find.byWidgetPredicate(
          (w) => w is ButtonStyleButton && w is! IconButton,
        );
        expect(controls, findsWidgets);
        for (final control in [controls.first, controls.last]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in mfaStates.keys) {
    testWidgets('$name: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openMfa(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and last controls reachable', (tester) async {
        await openMfa(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        final controls = find.byWidgetPredicate(
          (w) => w is ButtonStyleButton && w is! IconButton || w is DoorRow,
        );
        expect(controls, findsWidgets);
        for (final control in [controls.first, controls.last]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in dataStates.keys) {
    testWidgets('$name: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openData(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, the primary action reachable', (tester) async {
        await openData(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        final primary = find.byType(FilledButton);
        expect(primary, findsOneWidget);
        await tester.ensureVisible(primary);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final name in deleteStates.keys) {
    testWidgets('$name: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openDelete(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, every action reachable', (tester) async {
        await openDelete(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        final controls = find.byWidgetPredicate(
          (w) => (w is ButtonStyleButton && w is! IconButton) || w is DoorRow,
        );
        expect(controls, findsWidgets);
        for (final control in [controls.first, controls.last]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in childScreens.keys) {
    testWidgets('$name: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openChildScreen(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and primary controls reachable', (tester) async {
        await openChildScreen(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        // A confirmation covers its screen: only its own controls count.
        final dialog = find.byType(DestructiveConfirmation);
        Finder within(Finder f) => dialog.evaluate().isEmpty
            ? f
            : find.descendant(of: dialog, matching: f);
        final primary = within(find.byType(FilledButton));
        expect(primary, findsOneWidget);
        final first = within(
          find.byWidgetPredicate(
            (w) => w is DoorRow || w is TextField || w is DeclarationRow,
          ),
        );
        for (final control in [
          if (first.evaluate().isNotEmpty) first.first,
          primary,
        ]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in adultScreens.keys) {
    testWidgets('$name: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openAdultScreen(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and last controls reachable', (tester) async {
        await openAdultScreen(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        if (name.contains('long email')) expectWholeAddress(tester, size.width);
        // A task screen over the list: only its own controls count.
        final dialog = find.byType(Dialog);
        Finder within(Finder f) => dialog.evaluate().isEmpty
            ? f
            : find.descendant(of: dialog, matching: f);
        final first = within(
          find.byWidgetPredicate(
            (w) =>
                w is DoorRow ||
                w is TextField ||
                w is DeclarationRow ||
                w is FilledButton ||
                w is OutlinedButton,
          ),
        );
        // The column's last control: a quiet action, or the primary one.
        final last = within(
          find.byWidgetPredicate(
            (w) => w is ButtonStyleButton && w is! IconButton,
          ),
        );
        expect(last, findsWidgets);
        for (final control in [
          if (first.evaluate().isNotEmpty) first.first,
          last.last,
        ]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in invitationStates.keys) {
    testWidgets('$name: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openInvitation(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, its one action reachable', (tester) async {
        await openInvitation(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        if (name.contains('long')) expectWholeAddress(tester, size.width);
        // Past the back control: Entrar na família, Tentar de novo, or
        // the quiet way out.
        final action = find.byWidgetPredicate(
          (w) => w is ButtonStyleButton && w is! IconButton,
        );
        expect(action, findsWidgets);
        await tester.ensureVisible(action.last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final name in kidModeScreens.keys) {
    testWidgets('$name: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openKidModeScreen(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and last controls reachable', (tester) async {
        await openKidModeScreen(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        // The doors or the primary action; on the PIN pad, its keys up to
        // Confirmar.
        final controls = find.byWidgetPredicate(
          (w) => w is DoorRow || w is ButtonStyleButton && w is! IconButton,
        );
        expect(controls, findsWidgets);
        for (final control in [controls.first, controls.last]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in handOverScreens.keys) {
    final kid = handOverScreens[name]!.$3;
    testWidgets('$name: labelled controls with ${kid ? 64 : 48} dp targets', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openHandOverScreen(tester, name);

      await meetsGuidelines(tester);
      if (kid) await expectLater(tester, meetsGuideline(kidTapTargetGuideline));
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and last controls reachable', (tester) async {
        await openHandOverScreen(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        // The choices and the primary action; the PIN pad's keys and the
        // quiet foot; on the child home, its one control.
        final controls = find.byWidgetPredicate(
          (w) =>
              w is ChildChoice ||
              w is SelectableRow ||
              w is HoldToExit ||
              w is VideoTile ||
              w is PackTile ||
              w is PlayerKey ||
              w is ButtonStyleButton && w is! IconButton,
        );
        expect(controls, findsWidgets);
        for (final control in [controls.first, controls.last]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in screenTimeScreens.keys) {
    testWidgets('$name: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openScreenTime(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and last controls reachable', (tester) async {
        await openScreenTime(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        // The rows, the choices, the stepper's keys and the primary.
        final controls = find.byWidgetPredicate(
          (w) =>
              w is DoorRow && w.onTap != null ||
              w is SelectableRow ||
              w is ButtonStyleButton && w is! IconButton,
        );
        expect(controls, findsWidgets);
        for (final control in [controls.first, controls.last]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in catalogScreens.keys) {
    testWidgets('$name: labelled controls with 48 dp targets, every choice '
        'a radio', (tester) async {
      final semantics = tester.ensureSemantics();
      await openCatalog(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and last controls reachable', (tester) async {
        await openCatalog(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        final controls = find.byWidgetPredicate(
          (w) =>
              w is DoorRow && w.onTap != null ||
              w is SelectableRow ||
              w is ButtonStyleButton && w is! IconButton,
        );
        expect(controls, findsWidgets);
        for (final control in [controls.first, controls.last]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in curatorScreens.keys) {
    testWidgets('$name: labelled controls with 48 dp targets, every choice '
        'a radio', (tester) async {
      final semantics = tester.ensureSemantics();
      await openCurator(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and last controls reachable', (tester) async {
        await openCurator(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        // The doors, the choices, the field, the primary and "Ver mais".
        final controls = find.byWidgetPredicate(
          (w) =>
              w is DoorRow && w.onTap != null ||
              w is SelectableRow ||
              w is TextField ||
              w is ButtonStyleButton && w is! IconButton,
        );
        expect(controls, findsWidgets);
        for (final control in [controls.first, controls.last]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in adminScreens.keys) {
    testWidgets('$name: labelled controls with 48 dp targets, every choice '
        'a radio', (tester) async {
      final semantics = tester.ensureSemantics();
      await openAdmin(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and last controls reachable', (tester) async {
        await openAdmin(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        // The doors, the choices, the declaration, the field and the
        // actions, on the confirmation when one is open.
        final scope = find.byType(DestructiveConfirmation).evaluate().isEmpty
            ? find.byType(FieldLayout).first
            : find.byType(DestructiveConfirmation);
        final controls = find.descendant(
          of: scope,
          matching: find.byWidgetPredicate(
            (w) =>
                w is DoorRow && w.onTap != null ||
                w is SelectableRow ||
                w is DeclarationRow ||
                w is TextField ||
                w is ButtonStyleButton && w is! IconButton,
          ),
        );
        expect(controls, findsWidgets);
        for (final control in [controls.first, controls.last]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final name in suggestionScreens.keys) {
    testWidgets('$name: labelled controls with 48 dp targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await openSuggestions(tester, name);

      await meetsGuidelines(tester);
      semantics.dispose();
    });

    for (final size in [const Size(360, 640), const Size(1280, 800)]) {
      testWidgets('$name at 200% text, ${size.width.toInt()} wide: no '
          'overflow, first and last controls reachable', (tester) async {
        await openSuggestions(tester, name, size: size, textScale: 2);

        expect(tester.takeException(), isNull);
        // The field, the primary and the quiet retry.
        final controls = find.byWidgetPredicate(
          (w) => w is TextField || w is ButtonStyleButton && w is! IconButton,
        );
        expect(controls, findsWidgets);
        for (final control in [controls.first, controls.last]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('the hours\' picker at 200% text, ${size.width.toInt()} '
        'wide: no overflow in dial or keyboard entry, OK reachable', (
      tester,
    ) async {
      await openScreenTime(tester, 'limits', size: size, textScale: 2);

      await tapOn(tester, find.textContaining('Começa às'));
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'dial');
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'keyboard entry');
      await tester.ensureVisible(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('errors are a live region with an icon beside the text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ErrorNote('Algo deu errado.'))),
    );

    final node = tester.getSemantics(find.byType(ErrorNote));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('Algo deu errado.'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('at 200% text the entry field shrinks to a band and Entrar '
      'stays in the first viewport', (tester) async {
    await openRoute(
      tester,
      '/entrar',
      size: const Size(360, 640),
      textScale: 2,
    );

    final title = tester.getRect(find.text('Entrar').first);
    expect(title.top, lessThan(640));
    expect(find.text(promiseLine), findsOneWidget, reason: 'still said');
  });
  for (final MapEntry(key: title, value: open) in longTitles.entries) {
    testWidgets('"$title" at 200% text, 360 wide: the display title breaks '
        'only between words', (tester) async {
      await open(tester, const Size(360, 640), 2);

      expect(tester.takeException(), isNull);
      // The column inside the 24 px gutters.
      expectWholeWords(tester, title, 360 - 2 * Space.xl);
    });
  }
}

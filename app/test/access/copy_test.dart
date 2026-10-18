import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/forgot_password_screen.dart';
import 'package:telinha_segura/account/account_screen.dart';
import 'package:telinha_segura/account/email_screen.dart';
import 'package:telinha_segura/account/password_screen.dart';
import 'package:telinha_segura/account/sessions_screen.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/family/consent.dart';

ApiError err(String code, {List<String> reasons = const []}) =>
    ApiError(status: 400, code: code, reasons: reasons);

final banned = RegExp(
  r'!|100\s?%|garantid|totalmente segur|\bo senhor\b|\ba senhora\b',
  caseSensitive: false,
);

/// Children are named by their nickname.
final minorWords = RegExp(r'\bo menor\b|\bdependente', caseSensitive: false);

/// Every source whose string literals are copy.
List<File> scannedSources() => [
  File('lib/access/copy.dart'),
  ...Directory('lib/access').listSync().whereType<File>(),
  File('lib/design/field_layout.dart'),
  ...Directory('lib/family').listSync().whereType<File>(),
  ...Directory('lib/kid_mode').listSync().whereType<File>(),
  // The child side: no line there shouts either.
  ...Directory('lib/kid').listSync().whereType<File>(),
  ...Directory('lib/account').listSync().whereType<File>(),
  // The curation screens.
  ...Directory('lib/curation').listSync().whereType<File>(),
  // The staff screens (account directory screens).
  ...Directory('lib/staff').listSync().whereType<File>(),
];

/// The access, family, kid-mode, account, curation and staff screens'
/// sources and the shared copy they show, whose "e-mail" carries the word joiner.
List<File> wholeEmailSources() => [
  ...Directory('lib/access').listSync().whereType<File>(),
  ...Directory('lib/family').listSync().whereType<File>(),
  ...Directory('lib/kid_mode').listSync().whereType<File>(),
  ...Directory('lib/account').listSync().whereType<File>(),
  ...Directory('lib/curation').listSync().whereType<File>(),
  ...Directory('lib/staff').listSync().whereType<File>(),
];

void main() {
  test('an unknown code falls back to the generic retry copy', () {
    expect(Copy.forError(err('something_new')), Copy.genericRetry);
    expect(Copy.forError(StateError('socket')), Copy.genericRetry);
  });

  test('a lost platform role says which area closed', () {
    expect(
      Copy.forError(err('not_curator')),
      'Você não faz mais parte da curadoria.',
    );
    expect(
      Copy.forError(err('not_admin')),
      'Você não tem mais acesso à administração.',
    );
    expect(
      Copy.forError(err('not_moderator')),
      'Você não tem mais acesso à moderação.',
    );
  });

  test('invalid_credentials never says which field was wrong', () {
    final text = Copy.forError(err('invalid_credentials'));
    expect(text, isNot(contains('não existe')));
    expect(text.toLowerCase(), contains('e-\u2060mail ou a senha'));
  });

  test('a breached password is named as a known leak', () {
    expect(
      Copy.forError(err('weak_password', reasons: ['breached'])),
      contains('vazamento'),
    );
    expect(
      Copy.forError(err('weak_password', reasons: ['too_short'])),
      contains('15'),
    );
  });

  test('a screen may override a code for its context', () {
    expect(
      Copy.forError(
        err('invalid_token'),
        overrides: {'invalid_token': 'Este link expirou.'},
      ),
      'Este link expirou.',
    );
  });

  test('the countdown copy names whole seconds', () {
    expect(Copy.retryIn(const Duration(seconds: 42)), contains('42 s'));
    expect(Copy.retryIn(const Duration(seconds: 90)), contains('1 min 30 s'));
  });

  test('every family problem code has its own calm copy', () {
    const codes = [
      'email_unverified',
      'already_in_family',
      'no_family',
      'not_owner',
      'owner_must_transfer',
      'limit_reached',
      'policy_outdated',
      'invitation_email_mismatch',
      'invitation_unavailable',
      'already_member',
      'not_found',
      'reauth_required',
    ];
    final texts = {for (final c in codes) c: Copy.forError(err(c))};
    for (final MapEntry(:key, :value) in texts.entries) {
      expect(value, isNot(Copy.genericRetry), reason: key);
    }
    expect(texts.values.toSet(), hasLength(codes.length));
    expect(texts['policy_outdated'], contains('atualize o app'));
    expect(texts['not_owner'], contains('titular'));
    expect(texts['invitation_unavailable'], Copy.invitationGone);
  });

  test('every parental problem code has its own calm copy', () {
    const codes = [
      'pin_not_set',
      'kid_mode',
      'not_child',
      'profile_gone',
      'invalid_pin',
      'weak_pin',
    ];
    final texts = {for (final c in codes) c: Copy.forError(err(c))};
    final family = {
      for (final c in ['limit_reached', 'not_found', 'invalid_token'])
        Copy.forError(err(c)),
    };
    for (final MapEntry(:key, :value) in texts.entries) {
      expect(value, isNot(Copy.genericRetry), reason: key);
      expect(family, isNot(contains(value)), reason: key);
      expect(banned.hasMatch(value), isFalse, reason: key);
    }
    expect(texts.values.toSet(), hasLength(codes.length));
    expect(texts['invalid_pin'], 'PIN errado. Tente de novo.');
  });

  test('the screen-time codes have their own calm copy', () {
    expect(
      Copy.forError(err('over_cap')),
      'Hoje já chega a 4 horas, o máximo.',
    );
    final timeUp = Copy.forError(err('time_up'));
    expect(timeUp, isNot(Copy.genericRetry));
    expect(banned.hasMatch(timeUp), isFalse);
    // Read by an adult only: the child sees the sleeping picture, and
    // the window and the daily limit both answer it.
    expect(timeUp, isNot(contains('min')));
  });

  test('a paused profile asks for an adult\'s new authorization', () {
    expect(
      Copy.forError(err('consent_required')),
      'Este perfil precisa de uma nova autorização de um adulto.',
    );
  });

  test('the kid-mode screens word their own codes', () {
    for (final text in [Copy.pinRule, Copy.linkCodeGone, Copy.devicesFull]) {
      expect(banned.hasMatch(text), isFalse, reason: text);
      expect(text, isNot(Copy.genericRetry));
    }
    expect(Copy.pinRule, 'Use de 4 a 6 números.');
    expect(Copy.devicesFull, contains('10\u00A0aparelhos'));
    // Wrong or expired, and what to do: a new code on the adult's device.
    expect(Copy.linkCodeGone, contains('novo'));
    expect(
      Copy.forError(err('invalid_token'), overrides: Copy.linkCode),
      Copy.linkCodeGone,
    );
    expect(
      Copy.forError(err('limit_reached'), overrides: Copy.linkCode),
      Copy.devicesFull,
    );
    expect(
      scannedSources().map((f) => f.path),
      containsAll([
        'lib/kid_mode/kid_mode_screen.dart',
        'lib/kid_mode/set_pin_screen.dart',
      ]),
    );
  });

  test('the hand-over, the child side and the PIN gate are in the scan', () {
    expect(
      scannedSources().map((f) => f.path),
      containsAll([
        'lib/kid_mode/hand_over_screen.dart',
        'lib/kid_mode/pin_gate_screen.dart',
        'lib/kid/kid_home_screen.dart',
        'lib/kid/empty_shelf.dart',
        'lib/kid/kid_exit_screen.dart',
      ]),
    );
    expect(banned.hasMatch(Copy.familyGone), isFalse);
    expect(Copy.familyGone, contains('não existe mais'));
  });

  test('the consent text is in the scan, and passes it', () {
    final words = [
      ConsentText.title,
      ...ConsentText.paragraphs,
      ConsentText.declaration,
      ConsentText.reconsentTitle,
      ConsentText.reconsentDeclaration,
    ];
    for (final text in words) {
      expect(banned.hasMatch(text), isFalse, reason: text);
      expect(minorWords.hasMatch(text), isFalse, reason: text);
    }
    expect(
      scannedSources().map((f) => f.path),
      contains('lib/family/consent.dart'),
    );
  });

  test('the adults, invitations and deletion screens are in the scan', () {
    expect(
      scannedSources().map((f) => f.path),
      containsAll([
        'lib/family/adults_screen.dart',
        'lib/family/invitations_screen.dart',
        'lib/family/delete_family_screen.dart',
      ]),
    );
    for (final text in [Copy.adultsFull]) {
      expect(banned.hasMatch(text), isFalse, reason: text);
    }
  });

  test('the invitation screen and its copy are in the scan', () {
    expect(
      scannedSources().map((f) => f.path),
      contains('lib/family/accept_invitation_screen.dart'),
    );
    for (final text in [Copy.invitationGone, Copy.invitationFamilyFull]) {
      expect(banned.hasMatch(text), isFalse, reason: text);
    }
    // An invalid invitation says only that it is gone.
    expect(Copy.invitationGone, isNot(contains('@')));
  });

  test('the account screens are in both scans', () {
    expect(
      scannedSources().map((f) => f.path),
      contains('lib/account/account_screen.dart'),
    );
    expect(
      wholeEmailSources().map((f) => f.path),
      contains('lib/account/account_screen.dart'),
    );
    for (final text in [sessionsUnknown, sessionsWords(1), sessionsWords(3)]) {
      expect(banned.hasMatch(text), isFalse, reason: text);
      // Sessions are "aparelhos", never the child's linked devices.
      expect(text, isNot(contains('vinculad')), reason: text);
    }
  });

  test('the email and password screens are in both scans, with their '
      'copy', () {
    const sources = [
      'lib/account/email_screen.dart',
      'lib/account/password_screen.dart',
    ];
    expect(scannedSources().map((f) => f.path), containsAll(sources));
    expect(wholeEmailSources().map((f) => f.path), containsAll(sources));
    for (final text in [
      Copy.newEmailInvalid,
      Copy.currentPasswordWrong,
      emailLinkSent('bia@example.com', 'ana@example.com'),
      newEmailHelper,
      passwordChanged,
      createLeadIn,
      resetLinkSent,
    ]) {
      expect(banned.hasMatch(text), isFalse, reason: text);
      expect(text, isNot(contains('e-mail')), reason: text);
      expect(text, isNot(contains('vinculad')), reason: text);
    }
    // Each problem names what to do about it.
    expect(Copy.currentPasswordWrong, contains('atual'));
    expect(Copy.newEmailInvalid, contains('atual'));
  });

  test('the connected devices screen is in both scans, with its copy', () {
    const source = 'lib/account/sessions_screen.dart';
    expect(scannedSources().map((f) => f.path), contains(source));
    expect(wholeEmailSources().map((f) => f.path), contains(source));
    final now = DateTime(2026, 10, 4);
    for (final text in [
      loadingSessions,
      thisDevice,
      sessionEnded,
      othersAction,
      othersEnded,
      onlyThisDevice,
      allAction,
      Copy.sessionGone,
      sessionSince(DateTime(2026, 10, 1), now),
      sessionLastUse(DateTime(2026, 10, 1), now),
    ]) {
      expect(banned.hasMatch(text), isFalse, reason: text);
      // Sessions are connected devices, never the child's linked ones.
      expect(text, isNot(contains('vinculad')), reason: text);
      expect(text, isNot(contains('e-mail')), reason: text);
    }
    expect(loadingSessions, contains('aparelhos conectados'));
    // Sentence case: the actions start with a capital, then lower case.
    for (final action in [othersAction, allAction]) {
      expect(action.substring(1), action.substring(1).toLowerCase());
    }
    expect(
      Copy.forError(err('not_found')),
      isNot(Copy.sessionGone),
      reason: 'the session screen words its own not_found',
    );
  });

  test('the access screens are in the "e-mail" scan (Whole Word Rule)', () {
    expect(
      wholeEmailSources().map((f) => f.path),
      containsAll([
        'lib/access/copy.dart',
        'lib/access/check_email_screen.dart',
        'lib/access/verify_email_screen.dart',
        'lib/access/entry_screen.dart',
        'lib/access/email_sign_in_screen.dart',
        'lib/access/forgot_password_screen.dart',
      ]),
    );
  });

  test('no screen copy breaks "e-mail" at its hyphen', () {
    // The screens' sources and the shared copy they show; a word joiner
    // after the hyphen keeps the word whole on narrow lines.
    final sources = wholeEmailSources();
    final breakable = RegExp(r'e-mail', caseSensitive: false);
    final comment = RegExp(r'^\s*//.*$', multiLine: true);
    for (final file in sources) {
      final code = file.readAsStringSync().replaceAll(comment, '');
      for (final line in code.split('\n')) {
        expect(
          breakable.hasMatch(line),
          isFalse,
          reason: '${file.path}: $line',
        );
      }
    }
    expect(
      Copy.forError(err('invitation_email_mismatch')),
      contains('e-\u2060mail'),
    );
  });

  test('no curation copy parts a verb from its pronoun at the hyphen', () {
    // "recusá-lo" broken as "recusá-" / "lo." strands the pronoun (finish
    // review, 2026-10-05); a non-breaking hyphen keeps the word whole.
    final clitic = RegExp(r"[a-záéíóúâêôãõç]-(l[oa]s?|se|me|te|nos|lhe)\b");
    final comment = RegExp(r'^\s*//.*$', multiLine: true);
    for (final file in Directory('lib/curation').listSync().whereType<File>()) {
      final code = file.readAsStringSync().replaceAll(comment, '');
      for (final line in code.split('\n')) {
        expect(clitic.hasMatch(line), isFalse, reason: '${file.path}: $line');
      }
    }
  });

  test('no access or family copy shouts, guarantees, uses formal address or "o menor"', () {
    final sources = scannedSources();
    final literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'");
    final comment = RegExp(r'^\s*//.*$', multiLine: true);
    for (final file in sources) {
      final code = file.readAsStringSync().replaceAll(comment, '');
      for (final match in literal.allMatches(code)) {
        final text = match.group(1)!;
        if (!text.contains(' ')) continue; // identifiers, paths, codes
        expect(banned.hasMatch(text), isFalse, reason: '${file.path}: $text');
        expect(
          minorWords.hasMatch(text),
          isFalse,
          reason: '${file.path}: $text',
        );
      }
    }
  });
}

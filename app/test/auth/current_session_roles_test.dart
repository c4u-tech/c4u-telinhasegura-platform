import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/auth_api.dart';

import 'fakes.dart';

Map<String, Object?> sessionBody({Object? roles, bool withRoles = true}) => {
  'account': {'id': 'a1', 'email': 'ana@example.com', 'email_verified': true},
  'session': {'id': 's1', 'client': 'web'},
  'kid_mode': null,
  if (withRoles) 'roles': roles,
};

void main() {
  test('roles parse: none, one, both, unknown, missing', () async {
    Future<Set<PlatformRole>> roles(Map<String, Object?> body) async =>
        (await build(
          ClientKind.web,
          (_) => json(200, body),
        ).api.currentSession()).roles;

    expect(await roles(sessionBody(roles: <String>[])), isEmpty);
    expect(await roles(sessionBody(roles: ['admin'])), {PlatformRole.admin});
    expect(await roles(sessionBody(roles: ['admin', 'curator'])), {
      PlatformRole.admin,
      PlatformRole.curator,
    });
    expect(await roles(sessionBody(roles: ['owner', 'curator'])), {
      PlatformRole.curator,
    });
    expect(await roles(sessionBody(withRoles: false)), isEmpty);
    expect(await roles(sessionBody(roles: null)), isEmpty);
  });

  test('moderator parses; an unknown role is still skipped', () async {
    Future<Set<PlatformRole>> roles(Object? wire) async => (await build(
      ClientKind.web,
      (_) => json(200, sessionBody(roles: wire)),
    ).api.currentSession()).roles;

    expect(await roles(['moderator']), {PlatformRole.moderator});
    expect(await roles(['admin', 'curator', 'moderator']), {
      PlatformRole.admin,
      PlatformRole.curator,
      PlatformRole.moderator,
    });
    expect(await roles(['support', 'moderator']), {PlatformRole.moderator});
  });
}

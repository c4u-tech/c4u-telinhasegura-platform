import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/auth_api.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/family_api.dart';
import 'package:telinha_segura/family/family_model.dart';

import '../auth/fakes.dart';
import 'fixtures.dart';

http.Response account({
  bool verified = true,
  List<String> roles = const [],
  String status = 'active',
}) => json(200, {
  'account': {
    'id': 'a1',
    'email': 'ana@example.com',
    'email_verified': verified,
    'status': status,
  },
  'session': {'id': 's', 'client': 'web', 'csrf_token': 'c'},
  'roles': roles,
});

/// A model over a scripted API: [family] answers `GET /v1/family`, and
/// [calls] records every request.
({FamilyModel model, ApiClient client, List<String> calls}) build({
  http.Response Function()? session,
  http.Response Function()? family,
  FutureOr<http.Response> Function(http.Request)? other,
  Future<void>? gate,
}) {
  final calls = <String>[];
  final client = ApiClient(
    baseUrl: baseUrl,
    kind: ClientKind.web,
    httpClient: MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.method == 'GET' && req.url.path == '/v1/session') {
        return (session ?? account)();
      }
      if (req.method == 'GET' && req.url.path == '/v1/family') {
        await gate;
        return (family ?? () => json(200, ownerFamily))();
      }
      return await (other ?? noContent)(req);
    }),
  );
  client.rememberSession(csrfToken: 'c');
  final model = FamilyModel(
    auth: AuthApi(client),
    api: FamilyApi(client),
    status: client.status,
  );
  return (model: model, client: client, calls: calls);
}

void main() {
  test('starts loading and reads the account, then the family', () async {
    final b = build();
    expect(b.model.state, isA<FamilyLoading>());

    await b.model.load();

    final state = b.model.state as FamilyReady;
    expect(state.family.id, 'f1');
    expect(b.calls, ['GET /v1/session', 'GET /v1/family']);
  });

  test('load reads once; refresh reads the session and the family again '
      '(suspension screens)', () async {
    final b = build();
    await b.model.load();
    await b.model.load();
    expect(b.calls, hasLength(2));

    await b.model.refresh();

    expect(b.calls.sublist(2), ['GET /v1/session', 'GET /v1/family']);
  });

  test('an unverified account stops before the family', () async {
    final b = build(session: () => account(verified: false));

    await b.model.load();

    expect((b.model.state as EmailUnverified).email, 'ana@example.com');
    expect(b.calls, ['GET /v1/session']);
  });

  test(
    'a family read answering email_unverified shows the same prompt',
    () async {
      final b = build(family: () => problem(403, 'email_unverified'));

      await b.model.load();

      expect((b.model.state as EmailUnverified).email, 'ana@example.com');
    },
  );

  test('no_family on load is the first use, without a notice', () async {
    final b = build(family: () => problem(404, 'no_family'));

    await b.model.load();

    expect(b.model.state, isA<NoFamily>());
    expect(b.model.notice, isNull);
  });

  for (final (name, answer) in [
    ('a 5xx', () => problem(503, 'unavailable')),
    ('a dropped connection', () => throw http.ClientException('down')),
  ]) {
    test('$name fails the load, and retrying reads again', () async {
      var fail = true;
      final b = build(family: () => fail ? answer() : json(200, ownerFamily));

      await b.model.load();
      expect(b.model.state, isA<FamilyFailed>());

      fail = false;
      await b.model.refresh();
      expect(b.model.state, isA<FamilyReady>());
    });
  }

  test('a failed refresh keeps the family already shown', () async {
    var fail = false;
    final b = build(
      family: () => fail ? problem(500, 'internal') : json(200, ownerFamily),
    );
    await b.model.load();

    fail = true;
    await b.model.refresh();

    expect(b.model.state, isA<FamilyReady>());
  });

  test('create posts and holds the new family', () async {
    final b = build(
      family: () => problem(404, 'no_family'),
      other: (_) => json(201, ownerFamily),
    );
    await b.model.load();

    await b.model.create();

    expect(b.calls.last, 'POST /v1/family');
    expect((b.model.state as FamilyReady).family.id, 'f1');
  });

  test(
    'create answering email_unverified shows the prompt and throws',
    () async {
      final b = build(
        family: () => problem(404, 'no_family'),
        other: (_) => problem(403, 'email_unverified'),
      );
      await b.model.load();

      await expectLater(b.model.create(), throwsA(isA<ApiError>()));
      expect(b.model.state, isA<EmailUnverified>());
    },
  );

  test('create answering already_in_family reads the family it has', () async {
    var created = false;
    final b = build(
      family: () =>
          created ? json(200, ownerFamily) : problem(404, 'no_family'),
      other: (_) {
        created = true;
        return problem(409, 'already_in_family');
      },
    );
    await b.model.load();

    await b.model.create();

    expect(b.model.state, isA<FamilyReady>());
  });

  test('absorb turns no_family on any screen into the first use with a '
      'calm notice', () async {
    final b = build();
    await b.model.load();

    final absorbed = b.model.absorb(
      const ApiError(status: 404, code: 'no_family'),
    );

    expect(absorbed, isTrue);
    expect(b.model.state, isA<NoFamily>());
    expect(
      b.model.notice,
      Copy.forError(const ApiError(status: 404, code: 'no_family')),
    );
  });

  test('absorb takes email_unverified and leaves every other code', () async {
    final b = build();
    await b.model.load();

    expect(b.model.absorb(const ApiError(status: 409, code: 'x')), isFalse);
    expect(b.model.absorb(StateError('socket')), isFalse);
    expect(b.model.state, isA<FamilyReady>());

    expect(
      b.model.absorb(const ApiError(status: 403, code: 'email_unverified')),
      isTrue,
    );
    expect(b.model.state, isA<EmailUnverified>());
  });

  test('left returns to the first use without a notice', () async {
    final b = build();
    await b.model.load();

    b.model.left();

    expect(b.model.state, isA<NoFamily>());
    expect(b.model.notice, isNull);
  });

  group('notOwner', () {
    const notOwner = ApiError(status: 403, code: 'not_owner');

    test('reads the family again and, the caller now a guardian, keeps the '
        'not_owner copy for the home, once', () async {
      var role = 'owner';
      final b = build(family: () => json(200, {...ownerFamily, 'role': role}));
      await b.model.load();
      role = 'guardian';

      await b.model.notOwner(notOwner);

      expect((b.model.state as FamilyReady).family.role, FamilyRole.guardian);
      expect(b.model.takeNotice(), Copy.forError(notOwner));
      expect(b.model.takeNotice(), isNull);
    });

    test('still the owner after the read, there is nothing to carry', () async {
      final b = build();
      await b.model.load();

      await b.model.notOwner(notOwner);

      expect(b.calls.where((c) => c == 'GET /v1/family'), hasLength(2));
      expect(b.model.takeNotice(), isNull);
    });
  });

  test('joined holds the family and asks once for the rise', () async {
    final b = build(family: () => problem(404, 'no_family'));
    await b.model.load();

    b.model.joined(Family.fromJson(ownerFamily));

    expect(b.model.state, isA<FamilyReady>());
    expect(b.model.takeRise(), isTrue);
    expect(b.model.takeRise(), isFalse);
  });

  test('signing out forgets the family, so the next account reads its '
      'own', () async {
    final b = build();
    await b.model.load();
    b.model.absorb(const ApiError(status: 404, code: 'no_family'));
    expect(b.model.accountId, 'a1', reason: 'read with the session');

    await b.client.forgetSession();

    expect(b.model.state, isA<FamilyLoading>());
    expect(b.model.notice, isNull);
    expect(b.model.email, isNull);
    expect(b.model.accountId, isNull);
    b.client.rememberSession(csrfToken: 'c');
    await b.model.load();
    expect(b.calls.where((c) => c == 'GET /v1/session'), hasLength(2));
  });

  test('a read answering after a sign-out is dropped', () async {
    final gate = Completer<void>();
    final b = build(gate: gate.future);
    final reading = b.model.load();
    await pumpEventQueue();

    await b.client.forgetSession();
    gate.complete();
    await reading;

    expect(b.model.state, isA<FamilyLoading>());
  });

  group('platform roles', () {
    test('unknown until the account is read, then the session\'s', () async {
      final b = build(session: () => account(roles: ['curator']));
      expect(b.model.roles, isNull);

      await b.model.load();

      expect(b.model.roles, {PlatformRole.curator});
    });

    test('read with the account even when the email waits', () async {
      final b = build(
        session: () => account(verified: false, roles: ['admin']),
      );

      await b.model.load();

      expect(b.model.state, isA<EmailUnverified>());
      expect(b.model.roles, {PlatformRole.admin});
    });

    test('a guardian without a role has none', () async {
      final b = build();
      await b.model.load();
      expect(b.model.roles, isEmpty);
    });

    group('roleLost', () {
      for (final (code, lost) in [
        ('not_curator', {PlatformRole.curator}),
        ('not_admin', {PlatformRole.admin}),
        ('not_moderator', {PlatformRole.moderator, PlatformRole.admin}),
      ]) {
        test('$code drops the role at once, carries its copy for the home '
            'and reads the session again', () async {
          var roles = ['admin', 'curator', 'moderator'];
          final b = build(session: () => account(roles: roles));
          await b.model.load();
          roles = [
            for (final r in roles)
              if (!lost.any((l) => l.name == r)) r,
          ];
          final error = ApiError(status: 403, code: code);
          final seen = <Set<PlatformRole>?>[];
          b.model.addListener(() => seen.add(b.model.roles));

          final reading = b.model.roleLost(error);
          // The guard reacts before the read answers.
          expect(b.model.roles!.intersection(lost), isEmpty);
          await reading;

          expect(b.model.roles, PlatformRole.values.toSet()..removeAll(lost));
          expect(seen.first!.intersection(lost), isEmpty);
          expect(b.calls.where((c) => c == 'GET /v1/session'), hasLength(2));
          expect(b.model.takeNotice(), Copy.forError(error));
          expect(b.model.takeNotice(), isNull);
        });
      }

      test('a failed session read keeps the role dropped', () async {
        var fail = false;
        final b = build(
          session: () =>
              fail ? problem(500, 'internal') : account(roles: ['curator']),
        );
        await b.model.load();
        fail = true;

        await b.model.roleLost(
          const ApiError(status: 403, code: 'not_curator'),
        );

        expect(b.model.roles, isEmpty);
      });

      test('any other code is left alone', () async {
        final b = build(session: () => account(roles: ['curator']));
        await b.model.load();

        await b.model.roleLost(const ApiError(status: 404, code: 'not_found'));

        expect(b.model.roles, {PlatformRole.curator});
        expect(b.model.takeNotice(), isNull);
        expect(b.calls.where((c) => c == 'GET /v1/session'), hasLength(1));
      });
    });

    test('signing out forgets them', () async {
      final b = build(session: () => account(roles: ['curator']));
      await b.model.load();

      await b.client.forgetSession();

      expect(b.model.roles, isNull);
    });
  });

  group('pending invitations', () {
    http.Response list([List<Object> items = const [receivedInvitation]]) =>
        json(200, {'invitations': items});

    test('no_family shows the first use, then its invitations', () async {
      final b = build(
        family: () => problem(404, 'no_family'),
        other: (req) =>
            req.url.path == '/v1/invitations' ? list() : noContent(req),
      );

      await b.model.load();
      await pumpEventQueue();

      final state = b.model.state as NoFamily;
      expect(state.invitations.single.inviterEmail, 'carla@example.com');
      expect(b.calls, [
        'GET /v1/session',
        'GET /v1/family',
        'GET /v1/invitations',
      ]);
    });

    test('the first use shows before the list answers', () async {
      final gate = Completer<void>();
      final b = build(
        family: () => problem(404, 'no_family'),
        other: (req) async {
          await gate.future;
          return list();
        },
      );

      await b.model.load();

      expect((b.model.state as NoFamily).invitations, isEmpty);
      gate.complete();
      await pumpEventQueue();
      expect((b.model.state as NoFamily).invitations, hasLength(1));
    });

    for (final (name, answer) in [
      ('a 5xx', () => problem(503, 'unavailable')),
      ('a non-JSON answer', () => http.Response('', 204)),
    ]) {
      test('$name leaves the plain first use', () async {
        final b = build(
          family: () => problem(404, 'no_family'),
          other: (_) => answer(),
        );

        await b.model.load();
        await pumpEventQueue();

        expect((b.model.state as NoFamily).invitations, isEmpty);
      });
    }

    test('every read ending in no family reads the list again', () async {
      final b = build(
        family: () => problem(404, 'no_family'),
        other: (_) => list(),
      );
      await b.model.load();
      await pumpEventQueue();

      await b.model.refresh();
      await pumpEventQueue();

      expect(b.calls.where((c) => c == 'GET /v1/invitations'), hasLength(2));
    });

    test('a list answering after a family arrived is dropped', () async {
      final gate = Completer<void>();
      var hasFamily = false;
      final b = build(
        family: () =>
            hasFamily ? json(200, ownerFamily) : problem(404, 'no_family'),
        other: (_) async {
          await gate.future;
          return list();
        },
      );
      await b.model.load();

      hasFamily = true;
      await b.model.refresh();
      gate.complete();
      await pumpEventQueue();

      expect(b.model.state, isA<FamilyReady>());
    });

    test('a list answering after a sign-out is dropped', () async {
      final gate = Completer<void>();
      final b = build(
        family: () => problem(404, 'no_family'),
        other: (_) async {
          await gate.future;
          return list();
        },
      );
      await b.model.load();

      await b.client.forgetSession();
      gate.complete();
      await pumpEventQueue();

      expect(b.model.state, isA<FamilyLoading>());
    });

    test('a list answering for the account before is dropped', () async {
      final gate = Completer<void>();
      var reads = 0;
      final b = build(
        family: () => problem(404, 'no_family'),
        other: (_) async {
          if (reads++ == 0) {
            await gate.future;
            return list();
          }
          return list(const []);
        },
      );
      await b.model.load();

      await b.client.forgetSession();
      b.client.rememberSession(csrfToken: 'c');
      await b.model.load();
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();

      expect((b.model.state as NoFamily).invitations, isEmpty);
    });

    test('acceptById joins with the rise', () async {
      final b = build(
        family: () => problem(404, 'no_family'),
        other: (req) =>
            req.url.path == '/v1/invitations' ? list() : json(200, ownerFamily),
      );
      await b.model.load();
      await pumpEventQueue();

      await b.model.acceptById('i1');

      expect((b.model.state as FamilyReady).family.id, 'f1');
      expect(b.model.takeRise(), isTrue);
      expect(b.calls.last, 'POST /v1/invitations/i1/accept');
    });

    for (final code in ['invitation_unavailable', 'limit_reached']) {
      test('$code reads the list again and rethrows', () async {
        var items = <Object>[receivedInvitation];
        final b = build(
          family: () => problem(404, 'no_family'),
          other: (req) => req.url.path == '/v1/invitations'
              ? list(items)
              : problem(code == 'limit_reached' ? 409 : 404, code),
        );
        await b.model.load();
        await pumpEventQueue();
        items = [];

        await expectLater(
          b.model.acceptById('i1'),
          throwsA(isA<ApiError>().having((e) => e.code, 'code', code)),
        );

        expect((b.model.state as NoFamily).invitations, isEmpty);
        expect(b.calls.where((c) => c == 'GET /v1/invitations'), hasLength(2));
      });
    }

    test('already_in_family shows the family the account has', () async {
      var hasFamily = false;
      final b = build(
        family: () =>
            hasFamily ? json(200, ownerFamily) : problem(404, 'no_family'),
        other: (req) => req.url.path == '/v1/invitations'
            ? list()
            : problem(409, 'already_in_family'),
      );
      await b.model.load();
      await pumpEventQueue();
      hasFamily = true;

      await b.model.acceptById('i1');

      expect(b.model.state, isA<FamilyReady>());
    });

    test('left reads the invitations of the first use', () async {
      final b = build(
        other: (req) =>
            req.url.path == '/v1/invitations' ? list() : noContent(req),
      );
      await b.model.load();

      b.model.left();
      await pumpEventQueue();

      final state = b.model.state as NoFamily;
      expect(state.invitations.single.inviterEmail, 'carla@example.com');
      expect(b.calls, contains('GET /v1/invitations'));
    });

    test('acceptById answering after a sign-out is dropped', () async {
      final gate = Completer<void>();
      final b = build(
        family: () => problem(404, 'no_family'),
        other: (req) async {
          if (req.url.path == '/v1/invitations') return list();
          await gate.future;
          return json(200, ownerFamily);
        },
      );
      await b.model.load();
      await pumpEventQueue();

      final accepting = b.model.acceptById('i1');
      await pumpEventQueue();
      await b.client.forgetSession();
      gate.complete();
      await accepting;

      expect(b.model.state, isA<FamilyLoading>());
      expect(b.model.takeRise(), isFalse);
    });

    test('create answering after a sign-out is dropped', () async {
      final gate = Completer<void>();
      final b = build(
        family: () => problem(404, 'no_family'),
        other: (req) async {
          if (req.url.path == '/v1/invitations') return list();
          await gate.future;
          return json(201, ownerFamily);
        },
      );
      await b.model.load();
      await pumpEventQueue();

      final creating = b.model.create();
      await pumpEventQueue();
      await b.client.forgetSession();
      gate.complete();
      await creating;

      expect(b.model.state, isA<FamilyLoading>());
    });

    test('a refused acceptById after a sign-out reads nothing', () async {
      final gate = Completer<void>();
      final b = build(
        family: () => problem(404, 'no_family'),
        other: (req) async {
          if (req.url.path == '/v1/invitations') return list();
          await gate.future;
          return problem(404, 'invitation_unavailable');
        },
      );
      await b.model.load();
      await pumpEventQueue();

      final accepting = b.model.acceptById('i1');
      final refused = expectLater(accepting, throwsA(isA<ApiError>()));
      await pumpEventQueue();
      await b.client.forgetSession();
      b.calls.clear();
      gate.complete();
      await refused;
      await pumpEventQueue();

      expect(b.calls, isNot(contains('GET /v1/invitations')));
    });
  });

  group('account status', () {
    test(
      'active until read, then the session\'s, kept on every read',
      () async {
        var status = 'suspended';
        final b = build(session: () => account(status: status));
        expect(b.model.suspended, isFalse);

        await b.model.load();
        expect(b.model.suspended, isTrue);
        expect(b.model.state, isA<FamilyReady>(), reason: 'an owner needs it');

        status = 'active';
        await b.model.refresh();
        expect(b.model.suspended, isFalse, reason: 'reinstated');
      },
    );

    test(
      'suspended with no family: the first use, never the invitations',
      () async {
        final b = build(
          session: () => account(status: 'suspended'),
          family: () => problem(404, 'no_family'),
        );

        await b.model.load();
        await pumpEventQueue();
        b.model.left();
        await pumpEventQueue();

        expect(b.model.state, isA<NoFamily>());
        expect(b.calls, ['GET /v1/session', 'GET /v1/family']);
      },
    );

    test('suspended marks it at once and reads the session again', () async {
      var status = 'active';
      final b = build(session: () => account(status: status));
      await b.model.load();
      status = 'suspended';
      var notified = 0;
      b.model.addListener(() => notified++);

      final reading = b.model.accountSuspended();
      expect(b.model.suspended, isTrue);
      expect(notified, greaterThan(0));
      await reading;

      expect(b.calls.sublist(2), ['GET /v1/session', 'GET /v1/family']);
      expect(b.model.suspended, isTrue);
    });

    test('signing out forgets it', () async {
      final b = build(session: () => account(status: 'suspended'));
      await b.model.load();

      await b.client.forgetSession();

      expect(b.model.suspended, isFalse);
    });
  });
}

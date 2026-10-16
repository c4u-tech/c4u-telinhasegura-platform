import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/auth/auth_api.dart';
import 'package:telinha_segura/family/family_api.dart';
import 'package:telinha_segura/family/family_model.dart';
import 'package:telinha_segura/family/family_write.dart';

import '../auth/fakes.dart';
import 'fixtures.dart';

ApiError problemOf(String code, {Duration? retryAfter}) =>
    ApiError(status: 400, code: code, retryAfter: retryAfter);

/// A write over a model whose family reads are counted, with a scripted
/// re-authentication prompt.
({FamilyWrite write, FamilyModel model, List<String> reads, List<bool> asked})
build({bool confirms = true, bool ownerOnly = false, String role = 'owner'}) {
  final reads = <String>[];
  final client = ApiClient(
    baseUrl: baseUrl,
    kind: ClientKind.web,
    httpClient: MockClient((req) async {
      if (req.url.path == '/v1/session') {
        return json(200, {
          'account': {
            'id': 'a1',
            'email': 'ana@example.com',
            'email_verified': true,
          },
          'session': {'id': 's', 'client': 'web', 'csrf_token': 'c'},
        });
      }
      reads.add('${req.method} ${req.url.path}');
      return json(200, {...ownerFamily, 'role': role});
    }),
  );
  client.rememberSession(csrfToken: 'c');
  final model = FamilyModel(
    auth: AuthApi(client),
    api: FamilyApi(client),
    status: client.status,
  );
  final asked = <bool>[];
  final write = FamilyWrite(
    family: model,
    ownerOnly: ownerOnly,
    confirm: () async {
      asked.add(confirms);
      return confirms;
    },
  );
  return (write: write, model: model, reads: reads, asked: asked);
}

void main() {
  test('a write that succeeds returns true and leaves no message', () async {
    final b = build();
    var calls = 0;

    expect(await b.write.write(() async => calls++), isTrue);

    expect(calls, 1);
    expect(b.write.message, isNull);
    expect(b.write.busy, isFalse);
  });

  test('is busy while the write runs', () async {
    final b = build();
    final seen = <bool>[];

    await b.write.write(() async => seen.add(b.write.busy));

    expect(seen, [true]);
    expect(b.write.busy, isFalse);
  });

  test('reauth_required asks to confirm, then retries once', () async {
    final b = build();
    var calls = 0;

    final ok = await b.write.write(() async {
      if (calls++ == 0) throw problemOf('reauth_required');
    });

    expect(ok, isTrue);
    expect(calls, 2);
    expect(b.asked, [true]);
    expect(b.write.message, isNull);
  });

  test('a second reauth_required is not retried again', () async {
    final b = build();
    var calls = 0;

    final ok = await b.write.write(() async {
      calls++;
      throw problemOf('reauth_required');
    });

    expect(ok, isFalse);
    expect(calls, 2);
    expect(b.asked, [true]);
    expect(b.write.message, Copy.forError(problemOf('reauth_required')));
  });

  test('a cancelled confirmation leaves the action undone, idle and '
      'quiet', () async {
    final b = build(confirms: false);
    var calls = 0;

    final ok = await b.write.write(() async {
      calls++;
      throw problemOf('reauth_required');
    });

    expect(ok, isFalse);
    expect(calls, 1);
    expect(b.write.message, isNull);
    expect(b.write.blocked, isFalse);
  });

  test('no_family hands the error to the model, with its notice', () async {
    final b = build();

    final ok = await b.write.write(() async => throw problemOf('no_family'));

    expect(ok, isFalse);
    expect(b.model.state, isA<NoFamily>());
    expect(b.model.notice, Copy.forError(problemOf('no_family')));
    expect(b.write.message, isNull);
  });

  test('email_unverified hands the error to the model', () async {
    final b = build();

    await b.write.write(() async => throw problemOf('email_unverified'));

    expect(b.model.state, isA<EmailUnverified>());
    expect(b.write.message, isNull);
  });

  test('not_owner refreshes the family and says only the owner can', () async {
    final b = build();

    final ok = await b.write.write(() async => throw problemOf('not_owner'));
    await pumpEventQueue();

    expect(ok, isFalse);
    expect(b.reads, ['GET /v1/family']);
    expect(b.write.message, 'Só a pessoa titular da família pode fazer isso.');
  });

  test('on an owner-only screen, not_owner also carries its copy to the '
      'home the router leaves for', () async {
    final b = build(ownerOnly: true, role: 'guardian');
    await b.model.load();

    final ok = await b.write.write(() async => throw problemOf('not_owner'));
    await pumpEventQueue();

    expect(ok, isFalse);
    expect(b.model.takeNotice(), Copy.forError(problemOf('not_owner')));
  });

  test('elsewhere, not_owner carries nothing to the home', () async {
    final b = build(role: 'guardian');
    await b.model.load();

    await b.write.write(() async => throw problemOf('not_owner'));
    await pumpEventQueue();

    expect(b.model.takeNotice(), isNull);
  });

  test('any other problem becomes its copy, overrides first', () async {
    final b = build();

    await b.write.write(() async => throw problemOf('already_member'));
    expect(b.write.message, Copy.forError(problemOf('already_member')));

    await b.write.write(
      () async => throw problemOf('limit_reached'),
      overrides: const {'limit_reached': 'A família já tem 10 crianças.'},
    );
    expect(b.write.message, 'A família já tem 10 crianças.');

    await b.write.write(() async => throw Exception('offline'));
    expect(b.write.message, Copy.genericRetry);
  });

  test('a screen may place a problem itself', () async {
    final b = build();
    final placed = <String>[];

    await b.write.write(
      () async => throw problemOf('not_found'),
      handle: (e) {
        placed.add(e.code);
        return true;
      },
    );

    expect(placed, ['not_found']);
    expect(b.write.message, isNull);
  });

  test('rate_limited blocks the write behind its countdown', () async {
    final b = build();
    addTearDown(b.write.dispose);
    var calls = 0;

    await b.write.write(() async {
      calls++;
      throw problemOf('rate_limited', retryAfter: const Duration(seconds: 3));
    });
    expect(b.write.blocked, isTrue);
    expect(b.write.message, Copy.retryIn(const Duration(seconds: 3)));

    expect(await b.write.write(() async => calls++), isFalse);
    expect(calls, 1);
  });
}

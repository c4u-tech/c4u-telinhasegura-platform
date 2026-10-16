import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/account/account_write.dart';
import 'package:telinha_segura/auth/api_error.dart';

ApiError problemOf(String code, {Duration? retryAfter}) =>
    ApiError(status: 400, code: code, retryAfter: retryAfter);

/// A write with a scripted re-authentication prompt and a counted
/// sign-out.
({AccountWrite write, List<String> asked, List<String> signedOut}) build({
  bool confirms = true,
  bool? elevates,
  bool? enrolls,
}) {
  final asked = <String>[];
  final signedOut = <String>[];
  final write = AccountWrite(
    confirm: () async {
      asked.add('reauth');
      return confirms;
    },
    elevate: elevates == null
        ? null
        : () async {
            asked.add('elevate');
            return elevates;
          },
    enroll: enrolls == null
        ? null
        : () async {
            asked.add('enroll');
            return enrolls;
          },
    signOut: () async => signedOut.add('out'),
  );
  return (write: write, asked: asked, signedOut: signedOut);
}

void main() {
  test('a write that succeeds returns true and leaves no message', () async {
    final b = build();
    var calls = 0;

    expect(await b.write.write(() async => calls++), isTrue);

    expect(calls, 1);
    expect(b.write.message, isNull);
    expect(b.signedOut, isEmpty);
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
    expect(b.asked, ['reauth']);
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
    expect(b.write.message, Copy.forError(problemOf('reauth_required')));
  });

  test('a cancelled confirmation leaves the action undone and quiet', () async {
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

  test('unauthenticated signs the app out, quietly', () async {
    final b = build();

    final ok = await b.write.write(
      () async => throw problemOf('unauthenticated'),
    );
    await pumpEventQueue();

    expect(ok, isFalse);
    expect(b.signedOut, ['out']);
    expect(b.write.message, isNull);
  });

  test('a screen places its own codes; the rest become copy', () async {
    final b = build();

    await b.write.write(
      () async => throw problemOf('validation'),
      handle: (e) => e.code == 'validation',
    );
    expect(b.write.message, isNull);

    await b.write.write(() async => throw Exception('offline'));
    expect(b.write.message, Copy.genericRetry);
  });

  group('elevation', () {
    test(
      'elevation_required asks for the challenge, then retries once',
      () async {
        final b = build(elevates: true);
        var calls = 0;

        final ok = await b.write.write(() async {
          if (calls++ == 0) throw problemOf('elevation_required');
        });

        expect(ok, isTrue);
        expect(calls, 2);
        expect(b.asked, ['elevate']);
      },
    );

    test('both prompts, each once, in the order the server asks', () async {
      for (final order in [
        ['elevation_required', 'reauth_required'],
        ['reauth_required', 'elevation_required'],
      ]) {
        final b = build(elevates: true);
        var calls = 0;

        final ok = await b.write.write(() async {
          if (calls < order.length) throw problemOf(order[calls++]);
          calls++;
        });

        expect(ok, isTrue, reason: '$order');
        expect(calls, 3, reason: '$order');
        expect(b.asked, [
          for (final code in order)
            code == 'reauth_required' ? 'reauth' : 'elevate',
        ]);
      }
    });

    test('a second elevation_required is not asked again', () async {
      final b = build(elevates: true);
      var calls = 0;

      final ok = await b.write.write(() async {
        calls++;
        throw problemOf('elevation_required');
      });

      expect(ok, isFalse);
      expect(calls, 2);
      expect(b.asked, ['elevate']);
    });

    test('a cancelled challenge leaves the write undone and quiet', () async {
      final b = build(elevates: false);
      var calls = 0;

      final ok = await b.write.write(() async {
        calls++;
        throw problemOf('elevation_required');
      });

      expect(ok, isFalse);
      expect(calls, 1);
      expect(b.write.message, isNull);
    });

    test('without an elevate, elevation_required is the screen\'s', () async {
      final b = build();
      var handled = false;

      await b.write.write(
        () async => throw problemOf('elevation_required'),
        handle: (e) => handled = e.code == 'elevation_required',
      );

      expect(handled, isTrue);
      expect(b.asked, isEmpty);
    });
  });

  group('enrollment', () {
    test(
      'mfa_enrollment_required runs the enrollment, then retries once',
      () async {
        final b = build(elevates: true, enrolls: true);
        var calls = 0;

        final ok = await b.write.write(() async {
          if (calls++ == 0) throw problemOf('mfa_enrollment_required');
        });

        expect(ok, isTrue);
        expect(calls, 2);
        expect(b.asked, ['enroll']);
      },
    );

    test('with re-authentication after it, each once', () async {
      final b = build(elevates: true, enrolls: true);
      final order = ['mfa_enrollment_required', 'reauth_required'];
      var calls = 0;

      final ok = await b.write.write(() async {
        if (calls < order.length) throw problemOf(order[calls++]);
        calls++;
      });

      expect(ok, isTrue);
      expect(calls, 3);
      expect(b.asked, ['enroll', 'reauth']);
    });

    test('a cancelled enrollment leaves the write undone and quiet', () async {
      final b = build(elevates: true, enrolls: false);
      var calls = 0;

      final ok = await b.write.write(() async {
        calls++;
        throw problemOf('mfa_enrollment_required');
      });

      expect(ok, isFalse);
      expect(calls, 1);
      expect(b.write.message, isNull);
    });
  });
}

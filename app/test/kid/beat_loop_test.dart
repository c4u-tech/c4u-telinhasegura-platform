import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/kid/beat_loop.dart';
import 'package:telinha_segura/screentime/kid_time.dart';

const ok = KidTime(state: KidTimeState.ok, remaining: Duration(minutes: 10));

/// A periodic timer a test fires by hand.
class ManualTimer implements Timer {
  ManualTimer(this.callback);
  final void Function(Timer) callback;
  bool cancelled = false;
  void fire() => callback(this);
  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}

class Rig {
  Rig({this.onBeat, this.onReopen, this.sendPosition = false, this.position});

  final bool sendPosition;
  Future<int> Function()? position;

  final beats = <String>[];
  final timers = <ManualTimer>[];
  Future<KidTime> Function(String id, bool playing)? onBeat;
  Future<KidPlay> Function(String closed)? onReopen;
  var timeUps = 0;
  var doesNotFits = 0;
  var reopens = 0;
  final reopenedFrom = <String>[];

  late final loop = BeatLoop(
    playId: 'p1',
    sendPosition: sendPosition,
    position: () => position?.call() ?? Future.value(0),
    beat: (id, playing, at) {
      beats.add(at == null ? '$id $playing' : '$id $playing @$at');
      return onBeat?.call(id, playing) ?? Future.value(ok);
    },
    reopen: (closed) {
      reopens++;
      reopenedFrom.add(closed);
      return onReopen?.call(closed) ??
          Future.value(
            const KidPlay(
              playId: 'p2',
              youtubeId: 'yt1',
              remaining: Duration.zero,
            ),
          );
    },
    onTimeUp: () => timeUps++,
    onDoesNotFit: () => doesNotFits++,
    periodic: (interval, cb) {
      expect(interval, BeatLoop.interval);
      final t = ManualTimer(cb);
      timers.add(t);
      return t;
    },
  );
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  Future<KidTime> closedFor(String id, bool playing) =>
      Future.error(const ApiError(status: 409, code: 'play_closed'));

  test('beats on start, every tick, and once on pause', () async {
    final r = Rig();
    r.loop.playing();
    await settle();
    r.timers.single.fire();
    await settle();
    r.loop.paused();
    await settle();
    expect(r.beats, ['p1 true', 'p1 true', 'p1 false']);
    expect(r.timers.single.cancelled, isTrue);
    // A second pause, or a stop after it, sends nothing more.
    r.loop.paused();
    r.loop.stop();
    await settle();
    expect(r.beats, hasLength(3));
  });

  test('with sendPosition every beat carries where the video is', () async {
    var at = 754;
    final r = Rig(sendPosition: true, position: () async => at);
    r.loop.playing();
    await settle();
    at = 784;
    r.timers.single.fire();
    await settle();
    at = 790;
    r.loop.paused();
    await settle();
    expect(r.beats, ['p1 true @754', 'p1 true @784', 'p1 false @790']);
  });

  test('without sendPosition no beat carries a position', () async {
    var asked = 0;
    final r = Rig(
      position: () async {
        asked++;
        return 754;
      },
    );
    r.loop.playing();
    await settle();
    r.loop.paused();
    await settle();
    expect(r.beats, ['p1 true', 'p1 false']);
    expect(asked, 0);
  });

  test('a position that cannot be read still beats, without one', () async {
    final r = Rig(
      sendPosition: true,
      position: () => Future.error(StateError('no player')),
    );
    r.loop.playing();
    await settle();
    expect(r.beats, ['p1 true']);
  });

  test('the stop beat asks the position at once, before the player can '
      'close', () async {
    var closed = false;
    final r = Rig(sendPosition: true, position: () async => closed ? 0 : 812);
    r.loop.playing();
    await settle();
    r.loop.stop();
    // The screen closes the player in the same tick it stops the loop.
    closed = true;
    await settle();
    expect(r.beats, ['p1 true @812', 'p1 false @812']);
  });

  test('a stopped player answering 0 never sends 0 over the last position '
      'read', () async {
    var at = 754;
    final r = Rig(sendPosition: true, position: () async => at);
    r.loop.playing();
    await settle();
    r.timers.single.fire();
    at = 0;
    r.loop.stop();
    await settle();
    expect(r.beats, ['p1 true @754', 'p1 true @754', 'p1 false @754']);
  });

  test(
    'a stop whose position read fails sends the last position read',
    () async {
      var fail = false;
      final r = Rig(
        sendPosition: true,
        position: () =>
            fail ? Future.error(StateError('closed')) : Future.value(754),
      );
      r.loop.playing();
      await settle();
      fail = true;
      r.loop.stop();
      await settle();
      expect(r.beats, ['p1 true @754', 'p1 false @754']);
    },
  );

  test('a beat after a reopen carries the position too', () async {
    final r = Rig(
      sendPosition: true,
      position: () async => 900,
      onReopen: (_) async => const KidPlay(
        playId: 'p2',
        youtubeId: 'yt1',
        remaining: Duration.zero,
        startSeconds: 754,
        family: true,
      ),
      onBeat: (id, playing) => id == 'p1'
          ? Future.error(const ApiError(status: 409, code: 'play_closed'))
          : Future.value(ok),
    );
    r.loop.playing();
    await settle();
    await settle();
    expect(r.beats, ['p1 true @900', 'p2 true @900']);
  });

  test('a stop while playing beats false once', () async {
    final r = Rig();
    r.loop.playing();
    r.loop.stop();
    await settle();
    expect(r.beats, ['p1 true', 'p1 false']);
    r.loop.playing();
    await settle();
    expect(r.beats, hasLength(2));
  });

  test('play_closed reopens and carries on with the new play', () async {
    final r = Rig();
    r.onBeat = (id, _) => id == 'p1'
        ? Future.error(const ApiError(status: 409, code: 'play_closed'))
        : Future.value(ok);
    r.loop.playing();
    await settle();
    await settle();
    expect(r.loop.playId, 'p2');
    expect(r.beats, ['p1 true', 'p2 true']);
  });

  test('a reopen refused for time stops the loop and says so', () async {
    final r = Rig();
    r.onBeat = (_, _) =>
        Future.error(const ApiError(status: 409, code: 'play_closed'));
    r.onReopen = (_) =>
        Future.error(const ApiError(status: 403, code: 'time_up'));
    r.loop.playing();
    await settle();
    await settle();
    expect(r.timeUps, 1);
    expect(r.timers.single.cancelled, isTrue);
  });

  test('a reopen carries the closed play as continues', () async {
    final r = Rig();
    r.onBeat = (id, _) => id == 'p1'
        ? Future.error(const ApiError(status: 409, code: 'play_closed'))
        : Future.value(ok);
    r.loop.playing();
    await settle();
    await settle();
    expect(r.reopenedFrom, ['p1']);
  });

  test('a reopen refused for not fitting stops the loop and says so', () async {
    final r = Rig();
    r.onBeat = (_, _) =>
        Future.error(const ApiError(status: 409, code: 'play_closed'));
    r.onReopen = (_) =>
        Future.error(const ApiError(status: 403, code: 'does_not_fit'));
    r.loop.playing();
    await settle();
    await settle();
    expect(r.doesNotFits, 1);
    expect(r.timeUps, 0);
    expect(r.timers.single.cancelled, isTrue);
    // Stopped: a later play sends nothing and says nothing again.
    r.loop.playing();
    await settle();
    expect(r.beats, ['p1 true']);
    expect(r.doesNotFits, 1);
  });

  test(
    'a reopen refused for not fitting after a pause does not say so',
    () async {
      final r = Rig();
      r.onBeat = closedFor;
      r.onReopen = (_) =>
          Future.error(const ApiError(status: 403, code: 'does_not_fit'));
      r.loop.playing();
      r.loop.paused();
      await settle();
      await settle();
      expect(r.doesNotFits, 0);
    },
  );

  test(
    'a reopen refused for not fitting after a stop does not say so',
    () async {
      final r = Rig();
      final reopened = Completer<KidPlay>();
      r.onBeat = closedFor;
      r.onReopen = (_) => reopened.future;
      r.loop.playing();
      await settle();
      r.loop.stop();
      reopened.completeError(const ApiError(status: 403, code: 'does_not_fit'));
      await settle();
      await settle();
      expect(r.doesNotFits, 0);
    },
  );

  test('a time_up beat keeps the video playing', () async {
    final r = Rig();
    r.onBeat = (_, _) => Future.value(
      const KidTime(state: KidTimeState.timeUp, remaining: Duration.zero),
    );
    r.loop.playing();
    await settle();
    r.timers.single.fire();
    await settle();
    expect(r.timeUps, 0);
    expect(r.timers.single.cancelled, isFalse);
  });

  test('a network failure is quiet and the next tick beats again', () async {
    final r = Rig();
    var fail = true;
    r.onBeat = (_, _) {
      if (fail) {
        fail = false;
        return Future.error(Exception('offline'));
      }
      return Future.value(ok);
    };
    r.loop.playing();
    await settle();
    r.timers.single.fire();
    await settle();
    expect(r.beats, ['p1 true', 'p1 true']);
  });

  test('a stop beat answered play_closed does not reopen', () async {
    final r = Rig();
    r.onBeat = (_, playing) =>
        playing ? Future.value(ok) : closedFor('', false);
    r.loop.playing();
    r.loop.stop();
    await settle();
    await settle();
    expect(r.beats, ['p1 true', 'p1 false']);
    expect(r.reopens, 0);
  });

  test('a pause beat answered play_closed does not reopen', () async {
    final r = Rig();
    r.onBeat = (_, playing) =>
        playing ? Future.value(ok) : closedFor('', false);
    r.loop.playing();
    await settle();
    r.loop.paused();
    await settle();
    await settle();
    expect(r.reopens, 0);
    expect(r.timeUps, 0);
  });

  test('a reopen refused for time after a pause does not say so', () async {
    final r = Rig();
    r.onBeat = closedFor;
    r.onReopen = (_) =>
        Future.error(const ApiError(status: 403, code: 'time_up'));
    r.loop.playing();
    r.loop.paused();
    await settle();
    await settle();
    expect(r.timeUps, 0);
  });

  test(
    'after a reopen refused for time, a later playing() sends nothing',
    () async {
      final r = Rig();
      r.onBeat = closedFor;
      r.onReopen = (_) =>
          Future.error(const ApiError(status: 403, code: 'time_up'));
      r.loop.playing();
      await settle();
      await settle();
      r.loop.playing();
      await settle();
      expect(r.beats, ['p1 true']);
      expect(r.timers, hasLength(1));
    },
  );

  test('a beat that never answers does not stall the next tick', () {
    fakeAsync((async) {
      final r = Rig(
        onBeat: (id, playing) => r0.beats.length == 1
            ? Completer<KidTime>().future
            : Future.value(ok),
      );
      r0 = r;
      r.loop.playing();
      async.flushMicrotasks();
      expect(r.beats, ['p1 true']);
      r.timers.single.fire();
      async.elapse(BeatLoop.interval);
      async.flushMicrotasks();
      expect(r.beats, ['p1 true', 'p1 true']);
    });
  });
}

late Rig r0;

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
  Rig({this.onBeat, this.onReopen});

  final beats = <String>[];
  final timers = <ManualTimer>[];
  Future<KidTime> Function(String id, bool playing)? onBeat;
  Future<KidPlay> Function()? onReopen;
  var timeUps = 0;
  var reopens = 0;

  late final loop = BeatLoop(
    playId: 'p1',
    beat: (id, playing) {
      beats.add('$id $playing');
      return onBeat?.call(id, playing) ?? Future.value(ok);
    },
    reopen: () {
      reopens++;
      return onReopen?.call() ??
          Future.value(
            const KidPlay(
              playId: 'p2',
              youtubeId: 'yt1',
              remaining: Duration.zero,
            ),
          );
    },
    onTimeUp: () => timeUps++,
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
    r.onReopen = () =>
        Future.error(const ApiError(status: 403, code: 'time_up'));
    r.loop.playing();
    await settle();
    await settle();
    expect(r.timeUps, 1);
    expect(r.timers.single.cancelled, isTrue);
  });

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

  Future<KidTime> closedFor(String id, bool playing) =>
      Future.error(const ApiError(status: 409, code: 'play_closed'));

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
    r.onReopen = () =>
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
      r.onReopen = () =>
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

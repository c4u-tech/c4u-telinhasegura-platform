import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/draft_writer.dart';

void main() {
  test('the writer writes one at a time, the latest last, skipping '
      'superseded ones', () async {
    final saved = <int>[];
    final replies = <Completer<void>>[];
    final writer = DraftWriter<int>((v) {
      saved.add(v);
      final reply = Completer<void>();
      replies.add(reply);
      return reply.future;
    });

    writer
      ..write(1)
      ..write(2)
      ..write(3);
    expect(saved, [1], reason: 'one in flight at a time');
    var idle = false;
    unawaited(writer.idle.then((_) => idle = true));
    replies[0].complete();
    await pumpEventQueue();
    expect(saved, [1, 3]);
    expect(idle, isFalse, reason: '3 is still in flight');
    replies[1].complete();
    await pumpEventQueue();
    expect(saved, [1, 3]);
    expect(idle, isTrue);
    await writer.idle;
  });

  test('the writer swallows a refused write', () async {
    final saved = <int>[];
    final writer = DraftWriter<int>((v) async {
      saved.add(v);
      if (v == 1) {
        throw const ApiError(status: 409, code: 'already_reviewed');
      }
    });

    writer.write(1);
    await writer.idle;
    writer.write(2);
    await writer.idle;

    expect(saved, [1, 2]);
  });

  test('the writer lets a programming error through', () async {
    final errors = <Object>[];
    late DraftWriter<int> writer;
    await runZonedGuarded(() async {
      writer = DraftWriter<int>((_) async => throw StateError('broken'));
      writer.write(1);
      await writer.idle;
    }, (e, _) => errors.add(e));
    await pumpEventQueue();

    expect(errors, [isA<StateError>()]);
    await writer.idle;
  });

  test('an idle writer is idle at once', () async {
    final writer = DraftWriter<int>((_) async {});
    await writer.idle;
  });
}

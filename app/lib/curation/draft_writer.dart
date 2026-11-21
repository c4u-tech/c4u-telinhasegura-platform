import 'dart:async';

/// Writes a value through [save] one at a time: a value written while one
/// is in flight waits, and a newer one replaces it; a failed write is
/// dropped, since the next change writes again. An error that is not an
/// exception is a mistake in the app and goes through.
class DraftWriter<T> {
  DraftWriter(this._save);

  final Future<void> Function(T value) _save;
  bool _running = false;
  bool _waiting = false;
  T? _next;
  Completer<void>? _idle;

  void write(T value) {
    _next = value;
    _waiting = true;
    if (!_running) unawaited(_run());
  }

  /// Completes once nothing is in flight or waiting.
  Future<void> get idle =>
      _running ? (_idle ??= Completer<void>()).future : Future.value();

  Future<void> _run() async {
    _running = true;
    try {
      while (_waiting) {
        final value = _next as T;
        _waiting = false;
        _next = null;
        try {
          await _save(value);
        } on Exception {
          // Dropped: the next change writes the whole draft again.
        }
      }
    } finally {
      _running = false;
      _idle?.complete();
      _idle = null;
    }
  }
}

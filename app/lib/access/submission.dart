import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/api_error.dart';
import 'copy.dart';

/// One form's request lifecycle: busy while a request runs, a form-level
/// message after a failure, and a countdown after `rate_limited` that
/// keeps submit disabled until it reaches zero.
class Submission extends ChangeNotifier {
  bool _busy = false;
  String? _error;
  int? _wait;
  Timer? _timer;

  bool get busy => _busy;

  /// Busy, or waiting out a rate limit: submit stays disabled.
  bool get blocked => _busy || _wait != null;

  /// The form-level message: the countdown wins while it runs.
  String? get message =>
      _wait != null ? Copy.retryIn(Duration(seconds: _wait!)) : _error;

  /// Runs [action], returning whether it succeeded. A failure becomes the
  /// form message unless [handle] returns true for its `ApiError`, which
  /// means the screen placed it itself (on a field, say). Input is never
  /// cleared here.
  Future<bool> run(
    Future<void> Function() action, {
    Map<String, String> overrides = const {},
    bool Function(ApiError error)? handle,
  }) async {
    if (blocked) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on ApiError catch (e) {
      if (e.code == 'rate_limited') {
        _startWait(e.retryAfter ?? const Duration(seconds: 60));
      } else if (handle == null || !handle(e)) {
        _error = Copy.forError(e, overrides: overrides);
      }
      return false;
    } on Object {
      _error = Copy.genericRetry;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clearMessage() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  void _startWait(Duration wait) {
    _timer?.cancel();
    _wait = wait.inSeconds.clamp(1, 24 * 60 * 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = _wait! - 1;
      if (left <= 0) {
        t.cancel();
        _wait = null;
      } else {
        _wait = left;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

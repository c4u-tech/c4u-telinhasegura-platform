/// Runs async work at most once: concurrent and later calls share the
/// first run. A failed run is forgotten, so the next call retries it.
class Once {
  Once(this._work);

  final Future<void> Function() _work;
  Future<void>? _run;

  Future<void> call() => _run ??= _work().catchError((Object e) {
    _run = null;
    throw e;
  });
}

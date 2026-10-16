import 'package:clock/clock.dart';

/// What the app remembers of this session's privileged elevation, so the
/// admin and moderation routes' gate spares a status read while it lasts:
/// until the `elevated_until` the server last gave,
/// never past it, or for as long as the server does not ask for the
/// factor at all. It only spares a round trip: the server refuses with
/// `elevation_required` regardless, and the screens then ask again. It
/// shows nowhere, so there is no timer for the elevation's end.
class ElevationNote {
  DateTime? _until;
  bool _notAsked = false;

  final _asking = <Object, Future<bool>>{};

  /// Whether the gate may open a staff route without reading the status.
  bool get holds => _notAsked || (_until?.isAfter(clock.now()) ?? false);

  /// The session is elevated until [until].
  void elevated(DateTime until) => _until = until;

  /// The server does not ask this account for the factor (the switch is
  /// off, or the role does not need it).
  void notAsked() => _notAsked = true;

  /// The server refused, or the session changed: nothing is known.
  void forget() {
    _until = null;
    _notAsked = false;
  }

  /// Runs [ask] once for every caller asking with [key] while it runs, so
  /// reads refused together open one challenge, not one each.
  Future<bool> once(Object key, Future<bool> Function() ask) =>
      // A block body: `remove` answers the future, which would await itself.
      _asking[key] ??= ask().whenComplete(() {
        _asking.remove(key);
      });
}

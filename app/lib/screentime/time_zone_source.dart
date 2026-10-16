import 'package:flutter_timezone/flutter_timezone.dart';

/// The device's IANA zone, which a guardian's first screen-time save
/// sets for the family. A seam, so tests need no
/// platform channel.
abstract interface class TimeZoneSource {
  Future<String> current();
}

class PlatformTimeZone implements TimeZoneSource {
  @override
  Future<String> current() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}

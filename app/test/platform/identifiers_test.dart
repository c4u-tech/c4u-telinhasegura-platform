// No hardware or advertising identifier leaves the device;
// device_info_plus only labels sessions.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sources = [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart')) f,
  ];

  test('no source names a device identifier', () {
    final banned = RegExp(
      r'ANDROID_ID|androidId|identifierForVendor|advertisingId|'
      r'advertising_id|serialNumber|\.serial\b',
    );
    for (final f in sources) {
      expect(banned.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  test('only the device label reads device_info_plus', () {
    final readers = sources
        .where((f) => f.readAsStringSync().contains('package:device_info_plus'))
        .map((f) => f.path)
        .toList();
    expect(readers, ['lib/auth/device_label.dart']);
  });
}

import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart' show BrowserName;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/device_label.dart';

const windowsChrome =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, '
    'like Gecko) Chrome/129.0.0.0 Safari/537.36';
const macSafari =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.0 Safari/605.1.15';
const linuxFirefox =
    'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:131.0) Gecko/20100101 '
    'Firefox/131.0';
const androidChrome =
    'Mozilla/5.0 (Linux; Android 14; SM-S911B) AppleWebKit/537.36 (KHTML, '
    'like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36';
const iphoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 '
    'Safari/604.1';
const iphoneChrome =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/129.0.6668.69 '
    'Mobile/15E148 Safari/604.1';
const ipadSafari =
    'Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
const chromebook =
    'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, '
    'like Gecko) Chrome/129.0.0.0 Safari/537.36';

/// Platform reads a test scripts: each answers its record, or throws
/// when it is null; [calls] counts every read.
class FakeReads implements DeviceReads {
  FakeReads({this.androidInfo, this.iosInfo, this.browserInfo});

  final ({String manufacturer, String model})? androidInfo;
  final ({String modelName, String model})? iosInfo;
  final ({BrowserName browser, String? userAgent})? browserInfo;
  var calls = 0;

  @override
  Future<({String manufacturer, String model})> android() async {
    calls++;
    return androidInfo ?? (throw StateError('no android info'));
  }

  @override
  Future<({String modelName, String model})> ios() async {
    calls++;
    return iosInfo ?? (throw StateError('no ios info'));
  }

  @override
  Future<({BrowserName browser, String? userAgent})> browser() async {
    calls++;
    return browserInfo ?? (throw StateError('no browser info'));
  }
}

/// Android reads a test answers by hand: each call waits on its own
/// completer in [pending].
class HeldReads extends FakeReads {
  final pending = <Completer<({String manufacturer, String model})>>[];

  @override
  Future<({String manufacturer, String model})> android() {
    calls++;
    final c = Completer<({String manufacturer, String model})>();
    pending.add(c);
    return c.future;
  }
}

void main() {
  group('the coarse fallback', () {
    test('a coarse platform class names the device', () {
      expect(deviceLabelFor(TargetPlatform.android, web: false), 'Android');
      expect(deviceLabelFor(TargetPlatform.iOS, web: false), 'iPhone ou iPad');
    });

    test('on the web every platform is a browser', () {
      for (final platform in TargetPlatform.values) {
        expect(
          deviceLabelFor(platform, web: true),
          'Navegador',
          reason: '$platform',
        );
      }
    });

    test('a platform the app does not ship on sends no label, so the client '
        'kind names it', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(deviceLabelFor(platform, web: false), '', reason: '$platform');
      }
    });
  });

  group('Android names the maker and the model', () {
    test('the maker capitalized, then the model', () {
      expect(
        androidDeviceLabel(manufacturer: 'samsung', model: 'SM-S911B'),
        'Samsung SM-S911B',
      );
      expect(
        androidDeviceLabel(manufacturer: 'Google', model: 'Pixel 9'),
        'Google Pixel 9',
      );
      expect(
        androidDeviceLabel(manufacturer: 'motorola', model: 'moto g(60)'),
        'Motorola moto g(60)',
      );
    });

    test('a model that already starts with the maker is not doubled', () {
      expect(
        androidDeviceLabel(manufacturer: 'Xiaomi', model: 'Xiaomi 13'),
        'Xiaomi 13',
      );
      expect(
        androidDeviceLabel(manufacturer: 'HUAWEI', model: 'huawei P30'),
        'huawei P30',
      );
    });

    test('a missing part leaves the other; neither leaves the fallback', () {
      expect(androidDeviceLabel(manufacturer: '', model: 'Pixel 9'), 'Pixel 9');
      expect(androidDeviceLabel(manufacturer: 'samsung', model: ' '), '');
      expect(androidDeviceLabel(manufacturer: '', model: ''), '');
    });
  });

  group('iOS names the model as people know it', () {
    test('the known model name first', () {
      expect(
        iosDeviceLabel(modelName: 'iPhone 15', model: 'iPhone'),
        'iPhone 15',
      );
      expect(
        iosDeviceLabel(modelName: 'iPad Pro 11-Inch (M4)', model: 'iPad'),
        'iPad Pro 11-Inch (M4)',
      );
    });

    test('an unknown model falls back to the device class', () {
      expect(
        iosDeviceLabel(modelName: 'Unknown device', model: 'iPhone'),
        'iPhone',
      );
      expect(iosDeviceLabel(modelName: '', model: 'iPad'), 'iPad');
      expect(iosDeviceLabel(modelName: '', model: ''), '');
    });
  });

  group('the web names the browser and the system', () {
    test('browser "no" system', () {
      for (final (browser, agent, label) in [
        (BrowserName.chrome, windowsChrome, 'Chrome no Windows'),
        (BrowserName.safari, macSafari, 'Safari no Mac'),
        (BrowserName.firefox, linuxFirefox, 'Firefox no Linux'),
        (BrowserName.chrome, androidChrome, 'Chrome no Android'),
        (BrowserName.safari, iphoneSafari, 'Safari no iPhone'),
        (BrowserName.safari, ipadSafari, 'Safari no iPad'),
        (BrowserName.chrome, chromebook, 'Chrome no ChromeOS'),
        (BrowserName.edge, windowsChrome, 'Edge no Windows'),
        (
          BrowserName.samsungInternet,
          androidChrome,
          'Samsung Internet no Android',
        ),
        (BrowserName.opera, windowsChrome, 'Opera no Windows'),
      ]) {
        expect(
          webDeviceLabel(browser: browser, userAgent: agent),
          label,
          reason: label,
        );
      }
    });

    test('Chrome on an iPhone is Chrome, though it reports Safari', () {
      expect(
        webDeviceLabel(browser: BrowserName.safari, userAgent: iphoneChrome),
        'Chrome no iPhone',
      );
    });

    test('an unknown part is left out; both unknown is the fallback', () {
      expect(
        webDeviceLabel(browser: BrowserName.unknown, userAgent: windowsChrome),
        'Navegador no Windows',
      );
      expect(
        webDeviceLabel(browser: BrowserName.chrome, userAgent: null),
        'Chrome',
      );
      expect(
        webDeviceLabel(browser: BrowserName.unknown, userAgent: 'curl/8.0'),
        'Navegador',
      );
    });

    test('never a version, a build or the user-agent itself', () {
      final label = webDeviceLabel(
        browser: BrowserName.chrome,
        userAgent: androidChrome,
      );
      expect(label, isNot(contains(RegExp(r'\d'))));
      expect(label, isNot(contains('Mozilla')));
      expect(label, isNot(contains('SM-S911B')));
    });
  });

  test('a label holds at most 64 characters, whitespace collapsed', () {
    final label = androidDeviceLabel(
      manufacturer: 'samsung',
      model: 'SM-S911B   ${'x' * 80}',
    );
    expect(label.length, 64);
    expect(label, startsWith('Samsung SM-S911B x'));
    expect(
      androidDeviceLabel(manufacturer: 'a', model: '${'m' * 61} tail'),
      'A ${'m' * 61}',
      reason: 'no trailing space where the cut falls',
    );
  });

  group('this device\'s label', () {
    test('on Android, from the maker and the model', () async {
      final label = PlatformDeviceLabel(
        reads: FakeReads(
          androidInfo: (manufacturer: 'samsung', model: 'SM-S911B'),
        ),
        platform: TargetPlatform.android,
        web: false,
      );
      expect(await label.read(), 'Samsung SM-S911B');
    });

    test('on iOS, from the model name', () async {
      final label = PlatformDeviceLabel(
        reads: FakeReads(iosInfo: (modelName: 'iPhone 15', model: 'iPhone')),
        platform: TargetPlatform.iOS,
        web: false,
      );
      expect(await label.read(), 'iPhone 15');
    });

    test('on the web, from the browser, whatever the platform', () async {
      final label = PlatformDeviceLabel(
        reads: FakeReads(
          browserInfo: (browser: BrowserName.chrome, userAgent: windowsChrome),
        ),
        platform: TargetPlatform.android,
        web: true,
      );
      expect(await label.read(), 'Chrome no Windows');
    });

    test('a failed read, or one that names nothing, sends the coarse '
        'label', () async {
      for (final (platform, web, coarse) in [
        (TargetPlatform.android, false, 'Android'),
        (TargetPlatform.iOS, false, 'iPhone ou iPad'),
        (TargetPlatform.android, true, 'Navegador'),
      ]) {
        final failing = PlatformDeviceLabel(
          reads: FakeReads(),
          platform: platform,
          web: web,
        );
        expect(await failing.read(), coarse);
      }
      final empty = PlatformDeviceLabel(
        reads: FakeReads(androidInfo: (manufacturer: '', model: '')),
        platform: TargetPlatform.android,
        web: false,
      );
      expect(await empty.read(), 'Android');
    });

    test('a desktop the app does not ship on reads nothing and sends no '
        'label', () async {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        final reads = FakeReads();
        final label = PlatformDeviceLabel(
          reads: reads,
          platform: platform,
          web: false,
        );
        expect(await label.read(), '', reason: '$platform');
        expect(reads.calls, 0, reason: '$platform');
      }
    });

    test('is read once per run', () async {
      final reads = FakeReads(
        androidInfo: (manufacturer: 'Google', model: 'Pixel 9'),
      );
      final label = PlatformDeviceLabel(
        reads: reads,
        platform: TargetPlatform.android,
        web: false,
      );
      expect(await label.read(), 'Google Pixel 9');
      expect(await label.read(), 'Google Pixel 9');
      expect(reads.calls, 1);
    });

    test('a read slower than the sign-in sends the coarse label then, and '
        'the model once the read lands (cold start)', () async {
      final reads = HeldReads();
      final label = PlatformDeviceLabel(
        reads: reads,
        platform: TargetPlatform.android,
        web: false,
        patience: const Duration(milliseconds: 10),
      );
      expect(await label.read(), 'Android');
      reads.pending.single.complete((
        manufacturer: 'Google',
        model: 'sdk_gphone64_arm64',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(await label.read(), 'Google sdk_gphone64_arm64');
      expect(reads.calls, 1);
    });

    test('a failed read is tried again at the next sign-in', () async {
      final reads = HeldReads();
      final label = PlatformDeviceLabel(
        reads: reads,
        platform: TargetPlatform.android,
        web: false,
        patience: const Duration(milliseconds: 10),
      );
      final first = label.read();
      reads.pending.single.completeError(StateError('not ready'));
      expect(await first, 'Android');
      final second = label.read();
      reads.pending.last.complete((manufacturer: 'Google', model: 'Pixel 9'));
      expect(await second, 'Google Pixel 9');
      expect(reads.calls, 2);
    });

    test('follows the running platform by default', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final label = PlatformDeviceLabel(
        reads: FakeReads(iosInfo: (modelName: 'iPhone 15', model: 'iPhone')),
      );
      expect(await label.read(), 'iPhone 15');
    });
  });

  test('device_info_plus stays in the sign-in label, out of kid mode', () {
    final importers = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.readAsStringSync().contains('package:device_info_plus'))
          file.path,
    ];

    expect(importers, ['lib/auth/device_label.dart']);
  });

  test('the label reads only what names the model: never the owner\'s '
      'device name, an ID, a serial or an OS build', () {
    final code = File('lib/auth/device_label.dart').readAsStringSync();
    for (final field in [
      'info.name',
      'identifierForVendor',
      'serialNumber',
      'fingerprint',
      'systemVersion',
      'info.id',
      'info.display',
      'info.version',
      'utsname',
    ]) {
      expect(code, isNot(contains(field)), reason: field);
    }
  });
}

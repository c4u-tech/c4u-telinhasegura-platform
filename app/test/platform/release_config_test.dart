// Plain HTTP to a local API is a debug convenience; release builds keep
// the platforms' default refusal.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// The Flutter template's Icon-App-1024x1024@1x.png: 10932 bytes, SHA-256
// 7770183009e914112de7d8ef1d235a6a30c5834424858e0d2f8253f6b8d31926.
// package:crypto is only transitive, so the test compares the length.
const _flutterDefault1024Length = 10932;

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Android', () {
    test('release is signed by the upload key, never the debug key', () {
      final gradle = _read('android/app/build.gradle.kts');
      final release = RegExp(r'release\s*\{[^}]*\}')
          .allMatches(gradle)
          .map((m) => m.group(0)!)
          .join();
      expect(release, isNot(contains('getByName("debug")')));
      for (final name in [
        'ANDROID_KEYSTORE_PATH',
        'ANDROID_KEYSTORE_PASSWORD',
        'ANDROID_KEY_ALIAS',
        'ANDROID_KEY_PASSWORD',
      ]) {
        expect(gradle, contains(name));
      }
      expect(gradle, contains('key.properties'));
    });

    test('no manifest outside debug allows cleartext', () {
      final manifests = [
        for (final dir in Directory('android/app/src').listSync())
          if (dir is Directory && !dir.path.endsWith('/debug'))
            File('${dir.path}/AndroidManifest.xml'),
      ].where((f) => f.existsSync()).map((f) => f.path).toList();
      expect(manifests, contains('android/app/src/main/AndroidManifest.xml'));
      for (final path in manifests) {
        final xml = _read(path);
        expect(xml, isNot(contains('usesCleartextTraffic')), reason: path);
        expect(xml, isNot(contains('networkSecurityConfig')), reason: path);
      }
    });

    test('the debug manifest points at the debug network config', () {
      expect(
        _read('android/app/src/debug/AndroidManifest.xml'),
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
    });

    test('debug cleartext reaches the local hosts only', () {
      final xml = _read(
        'android/app/src/debug/res/xml/network_security_config.xml',
      );
      expect(xml, isNot(contains('<base-config')));
      final domains = RegExp(r'<domain[^>]*>([^<]+)</domain>')
          .allMatches(xml)
          .map((m) => m.group(1)!.trim())
          .toSet();
      expect(domains, {'10.0.2.2', 'localhost'});
      expect(xml, contains('cleartextTrafficPermitted="true"'));
    });

    test(
      'the main manifest asks for the network, never the advertising ID',
      () {
        final xml = _read('android/app/src/main/AndroidManifest.xml');
        expect(xml, contains('xmlns:tools="http://schemas.android.com/tools"'));
        expect(
          xml,
          contains(
            '<uses-permission android:name="android.permission.INTERNET"',
          ),
        );
        expect(
          RegExp(
            r'<uses-permission\s+android:name="com\.google\.android\.gms\.permission\.AD_ID"\s+tools:node="remove"\s*/>',
          ).hasMatch(xml),
          isTrue,
        );
        expect(xml, contains('android:label="Telinha Segura"'));
      },
    );
  });

  group('iOS', () {
    // The simulator reaches http://localhost without an exception,
    // so none is needed in any configuration.
    test('Info.plist carries no ATS exception', () {
      expect(
        _read('ios/Runner/Info.plist'),
        isNot(contains('NSAppTransportSecurity')),
      );
    });

    test('no xcconfig sets an ATS exception', () {
      for (final file in Directory('ios/Flutter').listSync()) {
        if (file is File && file.path.endsWith('.xcconfig')) {
          expect(
            file.readAsStringSync(),
            isNot(contains('NSAppTransportSecurity')),
            reason: file.path,
          );
        }
      }
    });

    test(
      'the privacy manifest declares no tracking and the data collected',
      () {
        final xml = _read('ios/Runner/PrivacyInfo.xcprivacy');
        expect(
          RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>').hasMatch(xml),
          isTrue,
        );
        expect(
          RegExp(r'<key>NSPrivacyTrackingDomains</key>\s*<array/>')
              .hasMatch(xml),
          isTrue,
        );
        for (final type in [
          'NSPrivacyCollectedDataTypeEmailAddress',
          'NSPrivacyCollectedDataTypeUserID',
          'NSPrivacyCollectedDataTypeOtherUserContent',
          'NSPrivacyCollectedDataTypeProductInteraction',
        ]) {
          expect(xml, contains(type));
        }
        expect(
          xml,
          isNot(
            contains('NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising'),
          ),
        );
        expect(
          _read('ios/Runner.xcodeproj/project.pbxproj'),
          contains('PrivacyInfo.xcprivacy in Resources'),
        );
      },
    );

    test('the app answers export compliance', () {
      expect(
        RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>')
            .hasMatch(_read('ios/Runner/Info.plist')),
        isTrue,
      );
    });

    test('both configurations take the team from Team.xcconfig', () {
      for (final c in ['Debug', 'Release']) {
        expect(
          _read('ios/Flutter/$c.xcconfig'),
          contains('#include "Team.xcconfig"'),
        );
      }
      expect(
        _read('ios/Flutter/Team.xcconfig'),
        matches(RegExp(r'^DEVELOPMENT_TEAM = ', multiLine: true)),
      );
    });
  });

  group('Brand', () {
    test('Android has an adaptive icon with a monochrome layer', () {
      final xml = _read(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      );
      expect(xml, contains('<adaptive-icon'));
      expect(xml, contains('<monochrome'));
      // The brand layers already carry their own padding: no extra inset.
      expect(xml, isNot(contains('android:inset="16%"')));
    });

    test('the iOS 1024 icon has no alpha channel', () {
      final dir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
      final big = dir.listSync().whereType<File>().where(
        (f) => f.path.contains('1024'),
      );
      expect(big, isNotEmpty);
      for (final f in big) {
        final bytes = f.readAsBytesSync();
        // PNG IHDR colour type at byte 25: 2 is RGB, 6 is RGBA.
        expect(bytes[25], 2, reason: f.path);
      }
    });

    test('the icons are the brand, not Flutter defaults', () {
      final brand = File('../brand/app-icon/app-icon-1024.png')
          .readAsBytesSync();
      final ios = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset')
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.contains('1024'))
          .readAsBytesSync();
      expect(brand, isNotEmpty);
      // The template icon is 10932 bytes; the brand icon is rewritten by
      // the generator and is a full 1024 x 1024 image (IHDR bytes 16-23).
      expect(ios.length, isNot(_flutterDefault1024Length));
      final header = ByteData.sublistView(Uint8List.fromList(ios));
      expect(header.getUint32(16), 1024);
      expect(header.getUint32(20), 1024);
    });

    test('the splash is the brand cream', () {
      final styles = _read('android/app/src/main/res/values-v31/styles.xml');
      expect(
        styles,
        matches(
          RegExp(
            r'windowSplashScreenBackground">#FBF6EC<',
            caseSensitive: false,
          ),
        ),
      );
      expect(
        _read('android/app/src/main/res/drawable/launch_background.xml'),
        contains('@drawable/background'),
      );
      // The pre-12 splash ground is a 1x1 PNG; read its pixel (RGB, 8 bit).
      final png = File('android/app/src/main/res/drawable/background.png')
          .readAsBytesSync();
      var offset = 8;
      final idat = <int>[];
      while (offset < png.length) {
        final length = ByteData.sublistView(png).getUint32(offset);
        final type = String.fromCharCodes(png.sublist(offset + 4, offset + 8));
        if (type == 'IDAT') {
          idat.addAll(png.sublist(offset + 8, offset + 8 + length));
        }
        offset += 12 + length;
      }
      // One scanline: filter byte, then R, G, B.
      expect(ZLibCodec().decode(idat).sublist(1, 4), [0xFB, 0xF6, 0xEC]);
    });
  });
}

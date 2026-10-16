import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/kid/player_fullscreen.dart';

void main() {
  bool decide(
    Size size, {
    TargetPlatform platform = TargetPlatform.android,
    bool web = false,
  }) => playerFullscreen(size: size, platform: platform, web: web);

  group('when the player goes fullscreen (fullscreen design)', () {
    test('a phone turned sideways, on Android and iOS', () {
      expect(decide(const Size(844, 390)), isTrue);
      expect(decide(const Size(640, 360)), isTrue);
      expect(
        decide(const Size(844, 390), platform: TargetPlatform.iOS),
        isTrue,
      );
    });

    test('a phone upright is not', () {
      expect(decide(const Size(390, 844)), isFalse);
    });

    test('a square screen is not sideways', () {
      expect(decide(const Size(500, 500)), isFalse);
    });

    test('a tablet in landscape keeps its rail', () {
      expect(decide(const Size(1280, 800)), isFalse);
      expect(decide(const Size(1024, 600)), isFalse);
      expect(
        decide(const Size(1194, 834), platform: TargetPlatform.iOS),
        isFalse,
      );
    });

    test('the web never does, whatever its size', () {
      expect(decide(const Size(844, 390), web: true), isFalse);
    });

    test('a desktop platform never does', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          decide(const Size(844, 390), platform: platform),
          isFalse,
          reason: '$platform',
        );
      }
    });
  });
}

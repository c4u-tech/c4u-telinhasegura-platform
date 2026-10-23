@Tags(['store_screens'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/labels.dart';

import '../access/harness.dart';
import '../catalog/fixtures.dart';
import '../family/fixtures.dart';
import '../kid_mode/devices_screen_test.dart' show device;
import '../screentime/fixtures.dart';

/// A device the stores ask screenshots of: its screen in logical pixels,
/// its pixel ratio and the platform the app adapts to.
class Profile {
  const Profile(this.name, this.logical, this.dpr, this.platform);
  final String name;
  final Size logical;
  final double dpr;
  final TargetPlatform platform;
}

const profiles = [
  Profile('android_phone', Size(412, 915), 2.625, TargetPlatform.android),
  Profile('android_tablet10', Size(800, 1280), 2, TargetPlatform.android),
  Profile('iphone61', Size(393, 852), 3, TargetPlatform.iOS),
  Profile('ipad13', Size(1032, 1376), 2, TargetPlatform.iOS),
];

/// One store frame: how to reach the real screen, and the phrases that must
/// be in the part of it the frame shows, so the caption is never ahead of
/// the screen.
class Frame {
  const Frame(this.number, this.mustShow, this.open);
  final String number;
  final List<String> mustShow;
  final Future<void> Function(WidgetTester tester, Size logical) open;
}

final outDir = Directory('build/store_screens/raw');

/// Three fictional children: Lia (fox, 5 to 8), Téo (owl, up to 4) and
/// Bia (cat, 9 to 12).
final demoFamily = familyWith([
  minorJson('m1', 'Lia'),
  minorJson('m2', 'Téo', avatar: 'owl', ageBand: 'ate-4'),
  minorJson('m3', 'Bia', avatar: 'cat', ageBand: '9-12'),
]);

/// The part of a capture a frame shows, as fractions of the capture: from
/// (x0, y0) across to x1 and down to the bottom edge.
class Crop {
  const Crop(this.x0, this.y0, this.x1);
  final double x0, y0, x1;

  static const whole = Crop(0, 0, 1);

  Rect on(Size logical) => Rect.fromLTRB(
    x0 * logical.width,
    y0 * logical.height,
    x1 * logical.width,
    logical.height,
  );
}

/// The crops compose.sh applies, by frame and profile; a frame without a
/// line shows the whole capture.
Map<String, Crop> readCrops() {
  final crops = <String, Crop>{};
  for (final line in File('store_screens/focus.tsv').readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final f = line.split('\t');
    crops['${f[0]}/${f[1]}'] = Crop(
      double.parse(f[2]),
      double.parse(f[3]),
      double.parse(f[4]),
    );
  }
  return crops;
}

final crops = readCrops();

Crop cropOf(Profile p, Frame f) => crops['${f.number}/${p.name}'] ?? Crop.whole;

Future<ByteData> _sdkFont(String path) async =>
    ByteData.sublistView(File(path).readAsBytesSync());

/// The app's own face, the icons and a Roboto fallback, so the captures
/// show real glyphs instead of the test font's squares.
Future<void> loadFonts() async {
  await (FontLoader(
    Typefaces.family,
  )..addFont(rootBundle.load('assets/fonts/BricolageGrotesque.ttf'))).load();
  // The test runner lives six levels under the Flutter root.
  var root = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    root = root.parent;
  }
  final fonts = '${root.path}/bin/cache/artifacts/material_fonts';
  final icons = File('$fonts/MaterialIcons-Regular.otf');
  final roboto = File('$fonts/Roboto-Regular.ttf');
  // Without them the captures would ship boxes for icons and text, so a
  // missing font stops the run instead of being skipped.
  for (final font in [icons, roboto]) {
    if (!font.existsSync()) {
      throw StateError('store screens: font not found at ${font.path}');
    }
  }
  await (FontLoader('MaterialIcons')..addFont(_sdkFont(icons.path))).load();
  for (final family in ['Roboto', 'FlutterTest']) {
    await (FontLoader(family)..addFont(_sdkFont(roboto.path))).load();
  }
}

Future<void> capture(WidgetTester tester, Profile p, Frame f) async {
  expect(
    find.byType(CircularProgressIndicator),
    findsNothing,
    reason: '${f.number} still loading',
  );
  final crop = cropOf(p, f);
  final viewport = Offset.zero & p.logical;
  final shown = crop.on(p.logical);
  for (final phrase in f.mustShow) {
    final finder = find.textContaining(phrase);
    expect(finder, findsWidgets, reason: '${f.number} must show "$phrase"');
    final rect = tester.getRect(finder.first);
    expect(
      _inside(rect, viewport),
      isTrue,
      reason: '${f.number}: "$phrase" at $rect is off the screen $viewport',
    );
    expect(
      _inside(rect, shown),
      isTrue,
      reason: '${f.number}: "$phrase" at $rect is outside the crop $shown',
    );
  }
  await tester.runAsync(() async {
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    // The frame enlarges its crop to the card's width, so the capture is
    // rendered that much denser: the shown part keeps at least the device's
    // pixel density and its text stays sharp.
    final image = await layer.toImage(
      viewport,
      pixelRatio: p.dpr / (crop.x1 - crop.x0),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${outDir.path}/${p.name}/${f.number}.png')
      ..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

bool _inside(Rect inner, Rect outer) =>
    inner.left >= outer.left - 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.bottom <= outer.bottom + 0.5;

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  final frames = <Frame>[
    // Lia's daily limit and the hours she may watch.
    Frame('02', ['Limite e horário', 'Começa às', 'Termina às'], (
      tester,
      size,
    ) async {
      final h = Harness(signedIn: true, api: screenTimeApi())
        ..family = demoFamily;
      await h.pump(tester, initial: '/familia/tempo/m1/limite', size: size);
    }),
    // The shared device locked to Lia asks for the parents' PIN.
    Frame('03', ['PIN dos pais'], (tester, size) async {
      final h = Harness(signedIn: true, api: (_) => http.Response('', 204))
        ..kidMode = {'minor_id': 'm1'}
        ..family = demoFamily;
      await h.pump(tester, initial: '/crianca/sair', size: size);
    }),
    // One row per child, the age band in words.
    Frame('04', ['5 a 8 anos', '2 a 4 anos', 'Bia'], (tester, size) async {
      final h = Harness(signedIn: true, api: catalogApi())..family = demoFamily;
      await h.pump(tester, initial: '/familia/videos', size: size);
    }),
    // The devices linked to each child.
    Frame('07', ['Tablet da Lia', 'Celular do Téo', 'Tablet da Bia'], (
      tester,
      size,
    ) async {
      final h = Harness(signedIn: true, api: (_) => http.Response('', 204))
        ..family = demoFamily
        ..pinSet = true;
      h.linkedDevices = [
        device('d1', 'Tablet da Lia', 'm1'),
        device('d2', 'Celular do Téo', 'm2', daysAgo: 1),
        device('d3', 'Tablet da Bia', 'm3'),
      ];
      unawaited(h.services.familyModel.load());
      await h.pump(tester, initial: '/modo-crianca/aparelhos', size: size);
    }),
    // The consent the guardian reads before a child's profile exists.
    Frame('08', ['apelido', 'avatar', 'faixa de idade', 'Nada de foto'], (
      tester,
      size,
    ) async {
      final h = Harness(signedIn: true, api: (_) => http.Response('', 204))
        ..family = demoFamily;
      unawaited(h.services.familyModel.load());
      await h.pump(tester, initial: '/familia/criancas/nova', size: size);
      await tester.enterText(find.byType(TextField), 'Téo');
      await tester.pumpAndSettle();
      await tapOn(tester, find.byKey(const ValueKey(Avatar.owl)));
      await tapOn(tester, find.text(AgeBand.upTo4.label));
      await tapOn(tester, find.text('Continuar'));
    }),
  ];
  for (final p in profiles) {
    for (final f in frames) {
      testWidgets('store frame ${f.number} on ${p.name}', (tester) async {
        debugDefaultTargetPlatformOverride = p.platform;
        try {
          await f.open(tester, p.logical);
          await tester.pumpAndSettle();
          await capture(tester, p, f);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}

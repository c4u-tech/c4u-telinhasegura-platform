// The status bar's style is sampled from the layer at the top of the
// screen, as the engine does. Guardian screens sit on the cream ground
// and need dark icons; kid screens sit on ink and need light ones. A
// style set by kid mode must not outlive it (iOS).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../access/harness.dart';
import '../kid/kid_home_screen_test.dart' show kidHome;

SystemUiOverlayStyle? statusBarStyle(WidgetTester tester) {
  final view = tester.binding.renderViews.first;
  final top = Offset(view.size.width / 2, 1);
  return view.debugLayer!.find<SystemUiOverlayStyle>(top);
}

void main() {
  testWidgets('a guardian screen asks for dark status bar icons', (
    tester,
  ) async {
    await Harness().pump(tester, initial: '/entrar');

    expect(statusBarStyle(tester), SystemUiOverlayStyle.dark);
  });

  testWidgets('a guardian screen in the dark theme asks for light icons', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await Harness().pump(tester, initial: '/entrar');

    expect(statusBarStyle(tester), SystemUiOverlayStyle.light);
  });

  testWidgets('a kid screen asks for light status bar icons', (tester) async {
    await kidHome(tester);

    expect(statusBarStyle(tester), SystemUiOverlayStyle.light);
  });
}

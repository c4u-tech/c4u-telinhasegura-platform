import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/kid/hold_to_exit.dart';
import 'package:telinha_segura/kid/tap_guard.dart';

/// A screen whose one button counts its taps, under a [TapGuard].
class _Counted extends StatelessWidget {
  const _Counted({
    required this.taps,
    this.label = 'Tocar',
    this.scene,
    this.focused = false,
  });

  final ValueNotifier<int> taps;
  final String label;
  final Object? scene;
  final bool focused;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TapGuard(
      scene: scene,
      child: Center(
        child: SizedBox.square(
          dimension: 200,
          child: TextButton(
            autofocus: focused,
            onPressed: () => taps.value++,
            child: Text(label),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a tap within 300 ms of the screen appearing is ignored; '
      'one after it lands', (tester) async {
    final taps = ValueNotifier(0);
    await tester.pumpWidget(MaterialApp(home: _Counted(taps: taps)));
    await tester.pump(const Duration(milliseconds: 290));
    await tester.tap(find.text('Tocar'), warnIfMissed: false);
    await tester.pump();
    expect(taps.value, 0);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.text('Tocar'));
    await tester.pump();
    expect(taps.value, 1);
  });

  testWidgets('the screen appearing again, once what covered it goes, '
      'ignores taps for the same moment', (tester) async {
    final taps = ValueNotifier(0);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: _Counted(taps: taps),
      ),
    );
    await tester.pump(TapGuard.window);
    unawaited(
      nav.currentState!.push(
        PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) =>
              _Counted(taps: ValueNotifier(0), label: 'Outra'),
        ),
      ),
    );
    await tester.pump(TapGuard.window);
    expect(find.text('Outra'), findsOneWidget);
    nav.currentState!.pop();
    await tester.pump();
    expect(find.text('Outra'), findsNothing);
    await tester.tap(find.text('Tocar'), warnIfMissed: false);
    await tester.pump();
    expect(taps.value, 0);
    await tester.pump(TapGuard.window);
    await tester.tap(find.text('Tocar'));
    await tester.pump();
    expect(taps.value, 1);
  });

  testWidgets('a screen reader\'s action is deliberate, never guarded', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final taps = ValueNotifier(0);
    await tester.pumpWidget(MaterialApp(home: _Counted(taps: taps)));
    tester.semantics.tap(find.semantics.byLabel('Tocar'));
    await tester.pump();
    expect(taps.value, 1);
    await tester.pump(TapGuard.window);
    handle.dispose();
  });

  testWidgets('the screen changing what it shows in place (a retry that '
      'brings the pictures) ignores taps for the same moment', (tester) async {
    final taps = ValueNotifier(0);
    await tester.pumpWidget(
      MaterialApp(
        home: _Counted(taps: taps, scene: 'failed'),
      ),
    );
    await tester.pump(TapGuard.window);
    await tester.tap(find.text('Tocar'));
    await tester.pump();
    expect(taps.value, 1);

    // The same scene again shuts nothing.
    await tester.pumpWidget(
      MaterialApp(
        home: _Counted(taps: taps, scene: 'failed'),
      ),
    );
    await tester.tap(find.text('Tocar'));
    await tester.pump();
    expect(taps.value, 2);

    await tester.pumpWidget(
      MaterialApp(
        home: _Counted(taps: taps, scene: 'pictures'),
      ),
    );
    await tester.tap(find.text('Tocar'), warnIfMissed: false);
    await tester.pump();
    expect(taps.value, 2);
    await tester.pump(TapGuard.window);
    await tester.tap(find.text('Tocar'));
    await tester.pump();
    expect(taps.value, 3);
  });

  testWidgets('a key pressed on the focused control is deliberate, never '
      'guarded', (tester) async {
    final taps = ValueNotifier(0);
    await tester.pumpWidget(
      MaterialApp(home: _Counted(taps: taps, focused: true)),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps.value, 1);
    await tester.pump(TapGuard.window);
  });

  testWidgets('a hold on the exit begun while touches wait never counts, '
      'even held past the moment: it must be begun again', (tester) async {
    var exits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TapGuard(
            child: Center(child: HoldToExit(onExit: () => exits++)),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final early = await tester.startGesture(
      tester.getCenter(find.byType(HoldToExit)),
    );
    await tester.pump();
    await tester.pump(TapGuard.window);
    await tester.pump(HoldToExit.hold + const Duration(milliseconds: 100));
    expect(exits, 0);
    await early.up();
    await tester.pump();

    final again = await tester.startGesture(
      tester.getCenter(find.byType(HoldToExit)),
    );
    await tester.pump(); // the press starts the clock
    await tester.pump(HoldToExit.hold + const Duration(milliseconds: 100));
    expect(exits, 1);
    await again.up();
    await tester.pump();
  });
}

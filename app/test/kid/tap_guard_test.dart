import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/kid/tap_guard.dart';

/// A screen whose one button counts its taps, under a [TapGuard].
class _Counted extends StatelessWidget {
  const _Counted({required this.taps, this.label = 'Tocar'});

  final ValueNotifier<int> taps;
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TapGuard(
      child: Center(
        child: SizedBox.square(
          dimension: 200,
          child: TextButton(onPressed: () => taps.value++, child: Text(label)),
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
}

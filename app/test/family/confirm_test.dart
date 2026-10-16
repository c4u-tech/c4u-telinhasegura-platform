import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/family/confirm.dart';

/// Opens a confirmation from a plain screen; [answer] holds what it
/// returned once closed.
class Opened {
  Object? answer = #open;
}

Future<Opened> open(
  WidgetTester tester,
  Future<Object?> Function(BuildContext) confirm, {
  Size size = const Size(360, 640),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = Opened();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => opened.answer = await confirm(context),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  return opened;
}

Future<Object?> reopening(BuildContext context) => confirmWithReason(
  context,
  title: 'Reabrir este vídeo para revisão?',
  body: const ['Ele volta para a fila da curadoria.'],
  action: 'Reabrir para revisão',
);

Finder get action => find.widgetWithText(FilledButton, 'Reabrir para revisão');
Finder get reason => find.widgetWithText(TextField, 'Motivo');

bool enabled(WidgetTester tester) =>
    tester.widget<FilledButton>(action).onPressed != null;

Future<void> confirm(WidgetTester tester) async {
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without a reason, the confirmation keeps today\'s anatomy '
      'and answers true', (tester) async {
    final opened = await open(
      tester,
      (context) => confirmDestructive(
        context,
        title: 'Remover?',
        body: const ['Sai de vez.'],
        action: 'Remover',
      ),
    );

    expect(find.byType(TextField), findsNothing);
    final remove = find.widgetWithText(FilledButton, 'Remover');
    expect(tester.widget<FilledButton>(remove).onPressed, isNotNull);
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(opened.answer, isTrue);
  });

  testWidgets('asks "Motivo" between what goes and the ink action, which '
      'waits on a reason of 3 to 200 characters', (tester) async {
    await open(tester, reopening);

    expect(reason, findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Ele volta para a fila da curadoria.')).dy,
      lessThan(tester.getTopLeft(reason).dy),
    );
    expect(
      tester.getTopLeft(reason).dy,
      lessThan(tester.getTopLeft(action).dy),
    );
    expect(enabled(tester), isFalse);
    expect(find.text(reasonHint), findsOneWidget);

    await tester.enterText(reason, '  ab  ');
    await tester.pump();
    expect(enabled(tester), isFalse, reason: 'two characters once trimmed');

    await tester.enterText(reason, 'abc');
    await tester.pump();
    expect(enabled(tester), isTrue);
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(
              of: find.text(reasonHint),
              matching: find.byType(Visibility),
            ),
          )
          .visible,
      isFalse,
    );
  });

  testWidgets('its count shows near the 200 bound, and the field holds no '
      'more', (tester) async {
    await open(tester, reopening);

    await tester.enterText(reason, 'a' * 150);
    await tester.pump();
    expect(find.textContaining('de 200'), findsNothing);

    await tester.enterText(reason, 'a' * 170);
    await tester.pump();
    expect(find.text('170 de 200'), findsOneWidget);

    await tester.enterText(reason, 'a' * 230);
    await tester.pump();
    expect(find.text('200 de 200'), findsOneWidget);
    expect(enabled(tester), isTrue);
  });

  testWidgets('confirmed, it answers the reason trimmed', (tester) async {
    final opened = await open(tester, reopening);

    await tester.enterText(reason, '  O canal corrigiu o vídeo.  ');
    await tester.pump();
    await confirm(tester);

    expect(opened.answer, 'O canal corrigiu o vídeo.');
    expect(find.byType(DestructiveConfirmation), findsNothing);
  });

  for (final (how, control) in [
    ('"Cancelar"', find.text('Cancelar')),
    ('the back control', find.byTooltip('Voltar')),
  ]) {
    testWidgets('cancelled with $how, it answers null', (tester) async {
      final opened = await open(tester, reopening);
      await tester.enterText(reason, 'Um motivo.');

      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      await tester.tap(control);
      await tester.pumpAndSettle();

      expect(opened.answer, isNull);
    });
  }

  testWidgets('holds at 200% text on a 360 × 640 phone', (tester) async {
    await open(tester, reopening, textScale: 2);

    await tester.enterText(reason, 'a' * 190);
    await tester.pump();
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(QuietAction, 'Cancelar'), findsOneWidget);
  });
}

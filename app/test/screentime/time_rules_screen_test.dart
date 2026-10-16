import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/design/value_stepper.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/screentime/time_rules_screen.dart';

import '../access/harness.dart';
import 'child_time_screen_test.dart' show liaFamily;
import 'fixtures.dart';

Future<Harness> timeRules(
  WidgetTester tester, {
  FutureOr<http.Response> Function()? rules,
  FutureOr<http.Response> Function(http.Request)? save,
  Size size = const Size(390, 844),
}) async {
  final h = Harness(
    signedIn: true,
    api: screenTimeApi(rules: {'m1': ?rules}, save: save),
  )..family = liaFamily;
  await h.pump(tester, initial: '/familia/tempo/m1/limite', size: size);
  return h;
}

Finder row(String title) => find.widgetWithText(DoorRow, title);

ValueStepper stepper(WidgetTester tester) =>
    tester.widget<ValueStepper>(find.byType(ValueStepper));

Future<void> tapOn(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Opens the picker from [from], types [hour]:[minute] in its input mode
/// and confirms.
Future<void> pick(
  WidgetTester tester,
  String from,
  int hour,
  int minute,
) async {
  await tapOn(tester, row(from));
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), '$hour');
  await tester.enterText(fields.at(1), '$minute'.padLeft(2, '0'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

const validationError = ApiError(status: 422, code: 'validation');

List<String> saves(Harness h) =>
    h.actions.where((c) => c.startsWith('PUT')).toList();

void main() {
  testWidgets('the limit in the stepper, the hours in two rows and the zone '
      'in words', (tester) async {
    await timeRules(tester);

    expect(find.text('Limite e horário'), findsOneWidget);
    final s = stepper(tester);
    expect(
      (s.label, s.value, s.min, s.max, s.step),
      ('Por dia', 90, 15, 240, 15),
    );
    expect(find.text('1 h 30 min'), findsOneWidget);
    expect(row('Começa às 08:00'), findsOneWidget);
    expect(row('Termina às 19:30'), findsOneWidget);
    expect(find.text('Horários de São Paulo'), findsOneWidget);
    expect(find.widgetWithText(PrimaryButton, 'Salvar'), findsOneWidget);
  });

  testWidgets('the stepper moves by 15 and waits at 240', (tester) async {
    await timeRules(
      tester,
      rules: () => json(200, rulesJson(dailyMinutes: 225)),
    );

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(find.text('4 h'), findsOneWidget);
    final plus = find.ancestor(
      of: find.byIcon(Icons.add_rounded),
      matching: find.byType(OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(plus).onPressed, isNull);
  });

  testWidgets('each row opens a 24-hour picker set to its time', (
    tester,
  ) async {
    await timeRules(tester);

    for (final (title, time) in [
      ('Começa às 08:00', const TimeOfDay(hour: 8, minute: 0)),
      ('Termina às 19:30', const TimeOfDay(hour: 19, minute: 30)),
    ]) {
      await tapOn(tester, row(title));
      final dialog = find.byType(TimePickerDialog);
      expect(tester.widget<TimePickerDialog>(dialog).initialTime, time);
      expect(
        MediaQuery.of(tester.element(dialog)).alwaysUse24HourFormat,
        isTrue,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a picked time shows on its row', (tester) async {
    await timeRules(tester);

    await pick(tester, 'Começa às 08:00', 7, 15);

    expect(row('Começa às 07:15'), findsOneWidget);
  });

  testWidgets('a start not before the end marks the Começa às row, its note '
      'under it, and calls nothing', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await timeRules(tester);
    await pick(tester, 'Começa às 08:00', 19, 30);

    await tapOn(tester, find.widgetWithText(PrimaryButton, 'Salvar'));

    expect(saves(h), isEmpty);
    // Field-level: on the row, not the screen's error note.
    expect(find.byType(ErrorNote), findsNothing);
    final start = row('Começa às 19:30');
    expect(tester.widget<DoorRow>(start).errorText, rangeRule);
    final note = find.descendant(of: start, matching: find.text(rangeRule));
    expect(note, findsOneWidget);
    final p = tester.element(start).palette;
    final text = Theme.of(tester.element(start)).textTheme;
    final noteStyle = tester.widget<Text>(note).style!;
    expect(noteStyle.color, p.error);
    expect(noteStyle.fontSize, text.bodySmall!.fontSize);
    expect(
      tester
          .widget<Text>(
            find.descendant(of: start, matching: find.text('Começa às 19:30')),
          )
          .style!
          .color,
      p.error,
    );
    // The note sits under the row's title, the row read with it, announced.
    expect(
      tester.getTopLeft(note).dy,
      greaterThan(tester.getBottomLeft(find.text('Começa às 19:30')).dy),
    );
    expect(
      tester.getSemantics(start),
      isSemantics(
        label: 'Começa às 19:30, $rangeRule',
        isLiveRegion: true,
        isButton: true,
      ),
    );
    // The zone line still follows the pair directly.
    final end = row('Termina às 19:30');
    final zone = find.text('Horários de São Paulo');
    expect(
      tester.getTopLeft(end).dy,
      greaterThan(tester.getBottomLeft(note).dy),
    );
    expect(
      tester.getTopLeft(zone).dy - tester.getBottomLeft(end).dy,
      lessThanOrEqualTo(Space.md + 1),
    );

    await pick(tester, 'Começa às 19:30', 9, 0);
    expect(find.text(rangeRule), findsNothing);
    expect(tester.widget<DoorRow>(row('Começa às 09:00')).errorText, isNull);
    semantics.dispose();
  });

  testWidgets('Salvar saves once and ends on the done state, back to the hub', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    final h = await timeRules(tester, save: (_) => answer.future);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await pick(tester, 'Termina às 19:30', 20, 0);

    final save = find.widgetWithText(PrimaryButton, 'Salvar');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pump();
    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();
    answer.complete(json(200, rulesJson(dailyMinutes: 105, end: '20:00')));
    await tester.pumpAndSettle();

    expect(saves(h), [
      'PUT /v1/screentime/minors/m1 {"daily_minutes":105,'
          '"window_start":"08:00","window_end":"20:00",'
          '"time_zone":"America/Sao_Paulo"}',
    ]);
    expect(
      find.text(
        'O limite de Lia agora é 1 h 45 min por dia, das 08:00 às 20:00.',
      ),
      findsOneWidget,
    );
    expect(find.byType(ValueStepper), findsNothing);
    await tapOn(tester, find.text('Voltar para o tempo de tela'));
    expect(h.location(tester), '/familia/tempo/m1');
  });

  testWidgets('a dropped save says so and keeps what was entered', (
    tester,
  ) async {
    await timeRules(tester, save: (_) => problem(503, 'unavailable'));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await pick(tester, 'Começa às 08:00', 9, 0);

    await tapOn(tester, find.widgetWithText(PrimaryButton, 'Salvar'));

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    expect(stepper(tester).value, 105);
    expect(row('Começa às 09:00'), findsOneWidget);
  });

  testWidgets('a validation with the hours in order reads as the generic '
      'validation, not the hours\' rule', (tester) async {
    await timeRules(tester, save: (_) => problem(422, 'validation'));

    await tapOn(tester, find.widgetWithText(PrimaryButton, 'Salvar'));

    expect(
      find.widgetWithText(ErrorNote, Copy.forError(validationError)),
      findsOneWidget,
    );
    expect(find.text(rangeRule), findsNothing);
  });

  testWidgets('rate_limited counts down with Salvar waiting', (tester) async {
    await timeRules(
      tester,
      save: (_) => problem(429, 'rate_limited', retryAfterBody: 3),
    );

    await tapOn(tester, find.widgetWithText(PrimaryButton, 'Salvar'));

    expect(find.text(Copy.retryIn(const Duration(seconds: 3))), findsOne);
    final save = find.widgetWithText(PrimaryButton, 'Salvar');
    expect(tester.widget<PrimaryButton>(save).onPressed, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<PrimaryButton>(save).onPressed, isNotNull);
  });

  testWidgets('a failed read says so, and Tentar de novo reads again', (
    tester,
  ) async {
    var fail = true;
    await timeRules(
      tester,
      rules: () => fail ? problem(503, 'unavailable') : json(200, rulesJson()),
    );

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    fail = false;
    await tapOn(tester, find.text('Tentar de novo'));

    expect(find.byType(ValueStepper), findsOneWidget);
  });

  testWidgets('a child that no longer exists goes back to the list with a '
      'notice', (tester) async {
    final h = await timeRules(tester, rules: () => problem(404, 'not_found'));

    expect(h.location(tester), '/familia/tempo');
    expect(find.text(Copy.childGone), findsOneWidget);
  });

  testWidgets('back returns to the hub', (tester) async {
    final h = await timeRules(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/tempo/m1');
  });

  test('the hours\' rule is the agreed words', () {
    expect(rangeRule, 'O começo precisa ser antes do fim.');
  });
}

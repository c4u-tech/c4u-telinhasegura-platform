import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/profile_fields.dart' show SelectableRow;
import 'package:telinha_segura/screentime/more_time_screen.dart';

import '../access/harness.dart';
import 'child_time_screen_test.dart' show liaFamily;
import 'fixtures.dart';

Future<Harness> moreTime(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? extend,
}) async {
  final h = Harness(signedIn: true, api: screenTimeApi(extend: extend))
    ..family = liaFamily;
  await h.pump(tester, initial: '/familia/tempo/m1/mais');
  return h;
}

Finder choice(String label) => find.widgetWithText(SelectableRow, label);

PrimaryButton primary(WidgetTester tester) =>
    tester.widget<PrimaryButton>(find.byType(PrimaryButton));

Future<void> choose(WidgetTester tester, String label) async {
  await tester.tap(choice(label));
  await tester.pumpAndSettle();
}

Future<void> give(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
}

List<String> extends_(Harness h) =>
    h.actions.where((c) => c.contains('/extend')).toList();

void main() {
  testWidgets('15, 30 and 60 minutes, none chosen; the primary waits with '
      'its hint', (tester) async {
    await moreTime(tester);

    final rows = tester.widgetList<SelectableRow>(find.byType(SelectableRow));
    expect(rows.map((r) => (r.label, r.selected)), [
      ('15 min', false),
      ('30 min', false),
      ('60 min', false),
    ]);
    expect(primary(tester).onPressed, isNull);
    expect(find.text(moreTimeHint), findsOneWidget);
  });

  testWidgets('choosing names the choice on the primary, and the hint keeps '
      'its place unseen', (tester) async {
    await moreTime(tester);
    final hintAt = tester.getTopLeft(find.text(moreTimeHint));

    await choose(tester, '30 min');

    expect(tester.widget<SelectableRow>(choice('30 min')).selected, isTrue);
    expect(primary(tester).label, 'Dar mais 30 min');
    expect(primary(tester).onPressed, isNotNull);
    final hint = tester.widget<SubmitHint>(find.byType(SubmitHint));
    expect((hint.visible, hint.reserve), (false, true));
    expect(tester.getTopLeft(find.text(moreTimeHint)), hintAt);

    await choose(tester, '60 min');
    expect(primary(tester).label, 'Dar mais 60 min');
    expect(tester.widget<SelectableRow>(choice('30 min')).selected, isFalse);
  });

  testWidgets('the choices read as radios', (tester) async {
    final semantics = tester.ensureSemantics();
    await moreTime(tester);

    expect(
      tester.getSemantics(choice('15 min')),
      isSemantics(
        label: '15 min',
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('the primary extends once and ends on the done state, back to '
      'the hub', (tester) async {
    final answer = Completer<http.Response>();
    final h = await moreTime(tester, extend: (_) => answer.future);
    await choose(tester, '30 min');

    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();
    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();
    answer.complete(json(200, {'state': 'ok', 'remaining_seconds': 1800}));
    await tester.pumpAndSettle();

    expect(extends_(h), [
      'POST /v1/screentime/minors/m1/extend {"minutes":30}',
    ]);
    expect(find.text('Lia tem mais 30 min hoje.'), findsOneWidget);
    expect(find.byType(SelectableRow), findsNothing);
    expect(find.text('Mais tempo hoje'), findsOneWidget);
    await tester.tap(find.text('Voltar para o tempo de tela'));
    await tester.pumpAndSettle();
    expect(h.location(tester), '/familia/tempo/m1');
  });

  testWidgets('over_cap says the day\'s maximum and keeps the choice', (
    tester,
  ) async {
    await moreTime(tester, extend: (_) => problem(409, 'over_cap'));
    await choose(tester, '60 min');

    await give(tester);

    expect(
      find.widgetWithText(ErrorNote, 'Hoje já chega a 4 horas, o máximo.'),
      findsOneWidget,
    );
    expect(tester.widget<SelectableRow>(choice('60 min')).selected, isTrue);
    expect(primary(tester).label, 'Dar mais 60 min');
  });

  testWidgets('a dropped call says so and keeps the choice', (tester) async {
    await moreTime(tester, extend: (_) => problem(503, 'unavailable'));
    await choose(tester, '15 min');

    await give(tester);

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOneWidget);
    expect(tester.widget<SelectableRow>(choice('15 min')).selected, isTrue);
  });

  testWidgets('rate_limited counts down with the primary waiting', (
    tester,
  ) async {
    await moreTime(
      tester,
      extend: (_) => problem(429, 'rate_limited', retryAfterBody: 3),
    );
    await choose(tester, '15 min');

    await give(tester);

    expect(find.text(Copy.retryIn(const Duration(seconds: 3))), findsOne);
    expect(primary(tester).onPressed, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(primary(tester).onPressed, isNotNull);
    expect(tester.widget<SelectableRow>(choice('15 min')).selected, isTrue);
  });

  testWidgets('a child that no longer exists goes back to the list with a '
      'notice', (tester) async {
    final h = await moreTime(tester, extend: (_) => problem(404, 'not_found'));
    await choose(tester, '15 min');

    await give(tester);

    expect(h.location(tester), '/familia/tempo');
    expect(find.text(Copy.childGone), findsOneWidget);
  });

  testWidgets('back returns to the hub', (tester) async {
    final h = await moreTime(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/tempo/m1');
  });
}

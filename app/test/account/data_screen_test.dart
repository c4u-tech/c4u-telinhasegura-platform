import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/account/account_screen.dart';
import 'package:telinha_segura/account/data_screen.dart';
import 'package:telinha_segura/privacy/export_delivery.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';

const exportRequest = 'GET /v1/account/export';

/// What the server answers for the export.
const document = {
  'format': 'telinhasegura.export/1',
  'account': {'email': 'ana@example.com'},
  'family': null,
};

/// Records each file handed over, answering [answer] (false: dismissed).
class Handover {
  bool answer = true;
  Object? error;
  final files = <ExportFile>[];
  final origins = <Rect?>[];

  Future<bool> call(ExportFile file, {Rect? origin}) async {
    files.add(file);
    origins.add(origin);
    if (error case final e?) throw e;
    return answer;
  }
}

/// `/conta/dados` for Ana. The export answers [answer] (the document by
/// default); the file goes to [handover] as a download, or as the share
/// sheet when [web] is false.
Future<Harness> dataScreen(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? answer,
  Handover? handover,
  bool web = true,
  Map<String, Object?>? family = ownerFamily,
}) async {
  final to = handover ?? Handover();
  final unused = Handover();
  final h = Harness(
    signedIn: true,
    exports: PlatformExportDelivery(
      web: web,
      download: web ? to.call : unused.call,
      share: web ? unused.call : to.call,
    ),
    api: (req) => switch (req.url.path) {
      '/v1/sessions' => json(200, {'sessions': <Object>[]}),
      _ when answer != null => answer(req),
      '/v1/account/export' => json(200, document),
      _ => http.Response('', 204),
    },
  )..family = family;
  await h.pump(tester, initial: '/conta/dados');
  expect(unused.files, isEmpty);
  return h;
}

Finder get download => find.widgetWithText(FilledButton, 'Baixar meus dados');

Future<void> tapDownload(WidgetTester tester) async {
  await tester.tap(download);
  await tester.pumpAndSettle();
}

/// The tests' "now": 23:30 on 4 October 2026, device time.
Future<void> atNight(Future<void> Function() body) =>
    withClock(Clock.fixed(DateTime(2026, 10, 4, 23, 30)), body);

void main() {
  testWidgets('lists what the copy holds, then Baixar meus dados', (
    tester,
  ) async {
    await dataScreen(tester);

    expect(find.byType(DataScreen), findsOneWidget);
    expect(find.text('Seus dados'), findsOneWidget);
    for (final item in exportContents) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    expect(exportContents, hasLength(6));
    expect(
      tester.getTopLeft(download).dy,
      greaterThan(tester.getBottomLeft(find.text(exportContents.last)).dy),
    );
  });

  testWidgets('works without a family and with the email unverified', (
    tester,
  ) async {
    final h = Harness(signedIn: true)..unverified = true;
    await h.pump(tester, initial: '/conta/dados');

    expect(find.byType(DataScreen), findsOneWidget);
    expect(download, findsOneWidget);
  });

  testWidgets('on the web, downloads the export as the day\'s JSON file, '
      'then says it is done', (tester) async {
    final handover = Handover();
    await atNight(() async {
      final h = await dataScreen(tester, handover: handover);

      await tapDownload(tester);

      expect(h.actions, [exportRequest]);
      final file = handover.files.single;
      expect(file.name, 'telinhasegura-dados-2026-10-04.json');
      expect(
        utf8.decode(file.bytes),
        const JsonEncoder.withIndent('  ').convert(document),
      );
      expect(find.text(exportDone), findsOneWidget);
      expect(download, findsNothing);
    });
  });

  testWidgets('on Android and iOS, opens the share sheet from the action', (
    tester,
  ) async {
    final handover = Handover();
    await atNight(() async {
      await dataScreen(tester, handover: handover, web: false);
      final action = tester.getRect(download);

      await tapDownload(tester);

      expect(handover.files.single.name, 'telinhasegura-dados-2026-10-04.json');
      expect(handover.origins.single, action);
      expect(find.text(exportDone), findsOneWidget);
    });
  });

  testWidgets('a dismissed share sheet is not done, and says nothing was '
      'shared', (tester) async {
    final handover = Handover()..answer = false;
    await dataScreen(tester, handover: handover, web: false);

    await tapDownload(tester);

    expect(find.text(exportDone), findsNothing);
    expect(find.text(exportDismissed), findsOneWidget);
    expect(find.byType(ErrorNote), findsNothing);
    expect(tester.widget<FilledButton>(download).onPressed, isNotNull);
  });

  testWidgets('a share sheet that fails says so, announced', (tester) async {
    final handover = Handover()..error = StateError('no sheet');
    await dataScreen(tester, handover: handover, web: false);

    await tapDownload(tester);

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOne);
    expect(find.text(exportDone), findsNothing);
  });

  testWidgets('the done state goes back to the account', (tester) async {
    await dataScreen(tester);

    await tapDownload(tester);
    await tester.tap(find.text('Voltar para sua conta'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
  });

  testWidgets('reauth_required asks to confirm it is you, then retries once', (
    tester,
  ) async {
    var confirmed = false;
    final handover = Handover();
    final h = await dataScreen(
      tester,
      handover: handover,
      answer: (req) {
        if (req.url.path == '/v1/session/reauth') {
          confirmed = true;
          return http.Response('', 204);
        }
        return confirmed
            ? json(200, document)
            : problem(403, 'reauth_required');
      },
    );

    await tapDownload(tester);
    expect(find.byType(ReauthPrompt), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'uma senha longa');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(h.actions.map((a) => a.split(' {').first), [
      exportRequest,
      'POST /v1/session/reauth',
      exportRequest,
    ]);
    expect(handover.files, hasLength(1));
    expect(find.text(exportDone), findsOneWidget);
  });

  testWidgets('a cancelled prompt keeps the screen, quietly', (tester) async {
    final handover = Handover();
    final h = await dataScreen(
      tester,
      handover: handover,
      answer: (_) => problem(403, 'reauth_required'),
    );

    await tapDownload(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(h.actions, [exportRequest]);
    expect(handover.files, isEmpty);
    expect(find.byType(ErrorNote), findsNothing);
    expect(tester.widget<FilledButton>(download).onPressed, isNotNull);
  });

  testWidgets('rate_limited shows its countdown and waits', (tester) async {
    final handover = Handover();
    await dataScreen(
      tester,
      handover: handover,
      answer: (_) =>
          problem(429, 'rate_limited', headers: {'retry-after': '90'}),
    );

    await tapDownload(tester);

    expect(
      find.widgetWithText(ErrorNote, Copy.retryIn(const Duration(seconds: 90))),
      findsOne,
    );
    expect(tester.widget<FilledButton>(download).onPressed, isNull);
    expect(handover.files, isEmpty);
    await tester.pump(const Duration(seconds: 91));
    expect(tester.widget<FilledButton>(download).onPressed, isNotNull);
  });

  testWidgets('a network failure or 5xx says so and delivers nothing', (
    tester,
  ) async {
    final handover = Handover();
    await dataScreen(
      tester,
      handover: handover,
      answer: (_) => problem(503, 'unavailable'),
    );

    await tapDownload(tester);

    expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOne);
    expect(handover.files, isEmpty);
  });

  testWidgets('the button waits, with progress, while the export runs', (
    tester,
  ) async {
    final answer = Completer<http.Response>();
    await dataScreen(tester, answer: (_) => answer.future);

    await tester.tap(download);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Baixar meus dados'), findsOneWidget);
    answer.complete(json(200, document));
    await tester.pumpAndSettle();
  });

  testWidgets('unauthenticated lands on the entry screen, signed out', (
    tester,
  ) async {
    await dataScreen(tester, answer: (_) => problem(401, 'unauthenticated'));

    await tapDownload(tester);

    expect(find.byType(EntryScreen), findsOneWidget);
  });

  testWidgets('the band\'s back control returns to the account', (
    tester,
  ) async {
    await dataScreen(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
  });
}

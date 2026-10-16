import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/account/account_screen.dart';
import 'package:telinha_segura/account/sessions_screen.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/auth_api.dart';
import 'package:telinha_segura/family/confirm.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'account_screen_test.dart' show sessionJson;

/// The tests' "now": Sunday 4 October 2026, mid-afternoon.
final now = DateTime(2026, 10, 4, 15);

/// This device's session and two others: the older one first, as the
/// server may list them.
List<Map<String, Object?>> threeSessions() => [
  sessionJson(
    'old',
    client: 'mobile',
    label: 'Android',
    lastSeen: DateTime.utc(2026, 9, 30, 12),
  ),
  sessionJson('here', current: true, lastSeen: DateTime.utc(2026, 10, 4, 12)),
  sessionJson(
    'recent',
    client: 'mobile',
    label: 'iPhone ou iPad',
    lastSeen: DateTime.utc(2026, 10, 3, 12),
  ),
];

/// `/conta/aparelhos` for Ana, listing [sessions] (this device and two
/// others by default). [read] replaces the list's answer; the other
/// calls answer [api], 204 by default, and an ended session leaves the
/// list.
Future<Harness> sessionsScreen(
  WidgetTester tester, {
  List<Map<String, Object?>>? sessions,
  FutureOr<http.Response> Function()? read,
  FutureOr<http.Response> Function(http.Request)? api,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  var listed = sessions ?? threeSessions();
  final h = Harness(
    signedIn: true,
    api: (req) {
      final path = req.url.path;
      if (req.method == 'GET' && path == '/v1/sessions') {
        return read?.call() ?? json(200, {'sessions': listed});
      }
      if (api != null) return api(req);
      if (req.method == 'DELETE' && path.startsWith('/v1/sessions/')) {
        final id = req.url.pathSegments.last;
        listed = [
          for (final s in listed)
            if (s['id'] != id) s,
        ];
      } else if (req.method == 'DELETE' && path == '/v1/sessions') {
        listed = [
          for (final s in listed)
            if (s['current'] == true) s,
        ];
      }
      return http.Response('', 204);
    },
  )..family = ownerFamily;
  await h.pump(
    tester,
    initial: '/conta/aparelhos',
    size: size,
    textScale: textScale,
  );
  return h;
}

/// Runs [body] with the clock fixed at [now].
Future<void> atNow(Future<void> Function() body) =>
    withClock(Clock.fixed(now), body);

/// The rows' titles, top to bottom.
List<String> titles(WidgetTester tester) => tester
    .widgetList<SessionRow>(find.byType(SessionRow))
    .map((r) => r.label)
    .toList();

Finder get endActions => find.widgetWithText(TextButton, 'Encerrar');

SessionSummary summary({
  String client = 'web',
  String label = '',
  bool current = false,
}) => SessionSummary(
  id: 's',
  client: client,
  deviceLabel: label,
  createdAt: DateTime.utc(2026, 10, 1, 12),
  lastSeenAt: DateTime.utc(2026, 10, 4, 12),
  isCurrent: current,
);

void main() {
  group('words', () {
    test('a session without a label is named by its client kind', () {
      expect(sessionName(summary(label: 'Android')), 'Android');
      expect(sessionName(summary(client: 'web')), 'Navegador');
      expect(sessionName(summary(client: 'mobile')), 'Celular ou tablet');
      expect(
        sessionName(summary(client: 'mobile', label: '  ')),
        'Celular '
        'ou tablet',
      );
    });

    test('since names the local day, with the year only when it is not '
        'this one', () {
      expect(
        sessionSince(DateTime(2026, 10, 1, 9), now),
        'desde 1º de outubro',
      );
      expect(sessionSince(DateTime(2026, 3, 12), now), 'desde 12 de março');
      expect(
        sessionSince(DateTime(2025, 12, 31, 23), now),
        'desde 31 de dezembro de 2025',
      );
    });

    test('last use counts calendar days on the device clock', () {
      expect(
        sessionLastUse(DateTime(2026, 10, 4, 0, 5), now),
        'último uso hoje',
      );
      expect(
        sessionLastUse(DateTime(2026, 10, 3, 23, 50), now),
        'último uso ontem',
      );
      expect(
        sessionLastUse(DateTime(2026, 9, 30, 12), now),
        'último uso há 4 dias',
      );
      // A clock behind the server's still reads "hoje".
      expect(sessionLastUse(DateTime(2026, 10, 5, 1), now), 'último uso hoje');
    });
  });

  group('the list', () {
    testWidgets('this device first, the others by last use, each with its '
        'dates', (tester) async {
      await atNow(() async {
        await sessionsScreen(tester);

        expect(find.byType(SessionsScreen), findsOneWidget);
        expect(find.text('Aparelhos conectados'), findsOneWidget);
        expect(titles(tester), ['Navegador', 'iPhone ou iPad', 'Android']);
        expect(find.text('este aparelho'), findsOneWidget);
        expect(find.text('último uso hoje'), findsOneWidget);
        expect(find.text('último uso ontem'), findsOneWidget);
        expect(find.text('último uso há 4 dias'), findsOneWidget);
        expect(find.text('desde 1º de outubro'), findsNWidgets(3));
      });
    });

    testWidgets('this device has no end action; every other does', (
      tester,
    ) async {
      await atNow(() async {
        await sessionsScreen(tester);

        expect(endActions, findsNWidgets(2));
        final current = find.widgetWithText(SessionRow, 'Navegador');
        expect(
          find.descendant(of: current, matching: find.byType(QuietAction)),
          findsNothing,
        );
      });
    });

    testWidgets('each row is led by a screen module, filled for this '
        'device only', (tester) async {
      await atNow(() async {
        await sessionsScreen(tester);

        final modules = tester
            .widgetList<StateModule>(
              find.descendant(
                of: find.byType(SessionRow),
                matching: find.byType(StateModule),
              ),
            )
            .map((m) => m.filled);
        expect(modules, [true, false, false]);
      });
    });

    testWidgets('each row reads its label, "este aparelho" when current, '
        'and its dates', (tester) async {
      final semantics = tester.ensureSemantics();
      await atNow(() async {
        await sessionsScreen(tester);

        for (final label in [
          'Navegador, este aparelho, desde 1º de outubro, último uso hoje',
          'iPhone ou iPad, desde 1º de outubro, último uso ontem',
          'Android, desde 1º de outubro, último uso há 4 dias',
        ]) {
          expect(find.bySemanticsLabel(label), findsOne, reason: label);
        }
      });
      semantics.dispose();
    });

    testWidgets('a session without a label shows its client kind', (
      tester,
    ) async {
      await atNow(() async {
        await sessionsScreen(
          tester,
          sessions: [
            sessionJson('here', current: true, label: ''),
            sessionJson('phone', client: 'mobile', label: ''),
          ],
        );

        expect(titles(tester), ['Navegador', 'Celular ou tablet']);
      });
    });

    testWidgets('waits calmly while the list loads', (tester) async {
      final answer = Completer<http.Response>();
      await sessionsScreen(tester, read: () => answer.future);

      expect(find.bySemanticsLabel(loadingSessions), findsOneWidget);
      expect(find.byType(SessionRow), findsNothing);

      answer.complete(json(200, {'sessions': threeSessions()}));
      await tester.pumpAndSettle();
      expect(find.byType(SessionRow), findsNWidgets(3));
    });

    testWidgets('a failed read says so calmly and tries again', (tester) async {
      var fail = true;
      await atNow(() async {
        await sessionsScreen(
          tester,
          read: () => fail
              ? problem(503, 'unavailable')
              : json(200, {'sessions': threeSessions()}),
        );

        expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOne);
        fail = false;
        await tester.tap(find.text('Tentar de novo'));
        await tester.pumpAndSettle();

        expect(find.byType(ErrorNote), findsNothing);
        expect(find.byType(SessionRow), findsNWidgets(3));
      });
    });

    testWidgets('a read that answers unauthenticated lands on the entry '
        'screen', (tester) async {
      await sessionsScreen(tester, read: () => problem(401, 'unauthenticated'));

      expect(find.byType(EntryScreen), findsOneWidget);
    });

    testWidgets('holds 24 sessions at 200% text without overflow', (
      tester,
    ) async {
      await atNow(() async {
        await sessionsScreen(
          tester,
          sessions: [
            sessionJson('here', current: true),
            for (var i = 0; i < 23; i++)
              sessionJson('s$i', client: 'mobile', label: 'iPhone ou iPad'),
          ],
          size: const Size(360, 640),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(endActions, findsWidgets);
        for (final control in [
          find.byType(SessionRow).last,
          find.text(othersAction),
          find.text(allAction),
        ]) {
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('the band\'s back control returns to the account', (
      tester,
    ) async {
      await atNow(() async {
        await sessionsScreen(tester);

        await tester.tap(find.byTooltip('Voltar'));
        await tester.pumpAndSettle();

        expect(find.byType(AccountScreen), findsOneWidget);
      });
    });
  });

  group('Encerrar', () {
    testWidgets('ends that session at once, with no confirmation, and its '
        'row goes', (tester) async {
      await atNow(() async {
        final h = await sessionsScreen(tester);

        await tester.tap(endActions.first);
        await tester.pumpAndSettle();

        expect(h.actions, ['DELETE /v1/sessions/recent']);
        expect(find.byType(Dialog), findsNothing);
        expect(titles(tester), ['Navegador', 'Android']);
        expect(find.text(sessionEnded), findsOneWidget);
      });
    });

    testWidgets('waits, with progress on its row, while the call runs', (
      tester,
    ) async {
      final answer = Completer<http.Response>();
      await atNow(() async {
        await sessionsScreen(
          tester,
          api: (req) =>
              req.method == 'DELETE' ? answer.future : http.Response('', 204),
        );

        await tester.tap(endActions.first);
        await tester.pump();

        final rows = tester.widgetList<SessionRow>(find.byType(SessionRow));
        expect(rows.map((r) => r.busy), [false, true, false]);
        // Every other write waits too.
        expect(rows.every((r) => r.current || r.onEnd == null), isTrue);

        answer.complete(http.Response('', 204));
        await tester.pumpAndSettle();
      });
    });

    testWidgets('a session already gone reloads the list and says so', (
      tester,
    ) async {
      await atNow(() async {
        var listed = threeSessions();
        final h = await sessionsScreen(
          tester,
          read: () => json(200, {'sessions': listed}),
          api: (req) {
            listed = [
              for (final s in listed)
                if (s['id'] == 'here') s,
            ];
            return problem(404, 'not_found');
          },
        );

        // The index under the screen reads the sessions too.
        int reads() => h.calls.where((c) => c == 'GET /v1/sessions').length;
        final before = reads();
        await tester.tap(endActions.first);
        await tester.pumpAndSettle();

        expect(h.actions, ['DELETE /v1/sessions/recent']);
        expect(reads(), before + 1);
        expect(titles(tester), ['Navegador']);
        expect(find.text(Copy.sessionGone), findsOneWidget);
        expect(find.byType(ErrorNote), findsNothing);
      });
    });

    testWidgets('a failure keeps the row and says so, announced', (
      tester,
    ) async {
      await atNow(() async {
        await sessionsScreen(tester, api: (_) => problem(503, 'unavailable'));

        await tester.tap(endActions.first);
        await tester.pumpAndSettle();

        expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOne);
        expect(titles(tester), ['Navegador', 'iPhone ou iPad', 'Android']);
      });
    });

    testWidgets('unauthenticated lands on the entry screen', (tester) async {
      await atNow(() async {
        await sessionsScreen(
          tester,
          api: (_) => problem(401, 'unauthenticated'),
        );

        await tester.tap(endActions.first);
        await tester.pumpAndSettle();

        expect(find.byType(EntryScreen), findsOneWidget);
      });
    });
  });

  group('Sair dos outros aparelhos', () {
    Finder others() => find.widgetWithText(FilledButton, othersAction);

    testWidgets('is the primary while others exist, below the list', (
      tester,
    ) async {
      await atNow(() async {
        await sessionsScreen(tester);

        expect(others(), findsOneWidget);
        expect(
          tester.getTopLeft(others()).dy,
          greaterThan(tester.getBottomLeft(find.byType(SessionRow).last).dy),
        );
        expect(find.text(onlyThisDevice), findsNothing);
      });
    });

    testWidgets('ends the others and reloads the list', (tester) async {
      await atNow(() async {
        final h = await sessionsScreen(tester);

        await tester.tap(others());
        await tester.pumpAndSettle();

        expect(h.actions, ['DELETE /v1/sessions?scope=others']);
        expect(titles(tester), ['Navegador']);
        expect(find.text(othersEnded), findsOneWidget);
        expect(find.text(onlyThisDevice), findsOneWidget);
        expect(others(), findsNothing);
      });
    });

    testWidgets('waits, with progress, while the call runs', (tester) async {
      final answer = Completer<http.Response>();
      await atNow(() async {
        await sessionsScreen(
          tester,
          api: (req) =>
              req.method == 'DELETE' ? answer.future : http.Response('', 204),
        );

        await tester.tap(others());
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(
          tester
              .widgetList<SessionRow>(find.byType(SessionRow))
              .every((r) => r.onEnd == null),
          isTrue,
        );

        answer.complete(http.Response('', 204));
        await tester.pumpAndSettle();
      });
    });

    testWidgets('a failure keeps the list and says so', (tester) async {
      await atNow(() async {
        await sessionsScreen(tester, api: (_) => problem(503, 'unavailable'));

        await tester.tap(others());
        await tester.pumpAndSettle();

        expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOne);
        expect(find.byType(SessionRow), findsNWidgets(3));
      });
    });

    testWidgets('alone, it says only this device is connected', (tester) async {
      await atNow(() async {
        await sessionsScreen(
          tester,
          sessions: [sessionJson('here', current: true)],
        );

        expect(onlyThisDevice, 'Só este aparelho está conectado.');
        expect(find.text(onlyThisDevice), findsOneWidget);
        expect(others(), findsNothing);
        expect(endActions, findsNothing);
      });
    });
  });

  group('Sair de todos os aparelhos', () {
    Finder all() => find.widgetWithText(TextButton, allAction);

    Future<void> openConfirmation(WidgetTester tester) async {
      await tester.ensureVisible(all());
      await tester.pumpAndSettle();
      await tester.tap(all());
      await tester.pumpAndSettle();
    }

    for (final (name, sessions) in [
      ('with others', threeSessions),
      ('alone', () => [sessionJson('here', current: true)]),
    ]) {
      testWidgets('is a quiet clay action at the foot, $name', (tester) async {
        await atNow(() async {
          await sessionsScreen(tester, sessions: sessions());

          final action = tester.widget<QuietAction>(
            find.widgetWithText(QuietAction, allAction),
          );
          expect(action.destructive, isTrue);
          expect(find.widgetWithText(FilledButton, allAction), findsNothing);
          expect(
            tester.getTopLeft(all()).dy,
            greaterThan(tester.getBottomLeft(find.byType(SessionRow).last).dy),
          );
        });
      });
    }

    testWidgets('asks first, saying this device is included and where you '
        'land', (tester) async {
      await atNow(() async {
        final h = await sessionsScreen(tester);

        await openConfirmation(tester);

        expect(find.byType(DestructiveConfirmation), findsOneWidget);
        expect(find.textContaining('inclusive este'), findsOneWidget);
        expect(find.textContaining('entrada'), findsOneWidget);
        expect(h.actions, isEmpty);
      });
    });

    testWidgets('cancelled, nothing happens', (tester) async {
      await atNow(() async {
        final h = await sessionsScreen(tester);

        await openConfirmation(tester);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        expect(h.actions, isEmpty);
        expect(find.byType(SessionsScreen), findsOneWidget);
      });
    });

    testWidgets('confirmed, ends every session and lands on the entry '
        'screen signed out', (tester) async {
      await atNow(() async {
        final h = await sessionsScreen(tester);

        await openConfirmation(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(DestructiveConfirmation),
            matching: find.widgetWithText(FilledButton, allAction),
          ),
        );
        await tester.pumpAndSettle();

        expect(h.actions, ['DELETE /v1/sessions?scope=all']);
        expect(find.byType(EntryScreen), findsOneWidget);
        expect(h.services.client.status.value, AuthStatus.signedOut);
      });
    });

    testWidgets('a failure keeps the screen and says so', (tester) async {
      await atNow(() async {
        await sessionsScreen(tester, api: (_) => problem(503, 'unavailable'));

        await openConfirmation(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(DestructiveConfirmation),
            matching: find.widgetWithText(FilledButton, allAction),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SessionsScreen), findsOneWidget);
        expect(find.widgetWithText(ErrorNote, Copy.genericRetry), findsOne);
      });
    });
  });
}

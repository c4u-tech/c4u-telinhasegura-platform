import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/design/band_transition.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/kid_mode/redeem_screen.dart';
import 'package:telinha_segura/parental/app_mode.dart';
import 'package:telinha_segura/shell/services.dart';

import '../access/harness.dart';
import '../parental/fakes.dart';
import '../parental/parental_api_test.dart' show profileJson;
import 'hand_over_screen_test.dart' show pumpUntil, tapOn;
import 'link_code_screen_test.dart' show strandable;

/// A child's phone, signed out and unlinked, at `/vincular-aparelho`
/// ([initial] may carry `?codigo=`). Redemption answers [answer] (a
/// device for Lia by default).
Future<Harness> redeem(
  WidgetTester tester, {
  String initial = '/vincular-aparelho',
  FutureOr<http.Response> Function(http.Request)? answer,
  MemoryDeviceCredentialStore? devices,
}) async {
  final h = Harness(
    kind: ClientKind.mobile,
    devices: devices ?? MemoryDeviceCredentialStore(),
    api: (req) => switch (req.url.path) {
      '/v1/devices/redeem' =>
        answer?.call(req) ??
            json(201, {'token': 'dev-token', 'profile': profileJson}),
      '/v1/child/profile' => json(200, profileJson),
      _ => http.Response('', 204),
    },
  );
  await h.pump(tester, initial: initial);
  return h;
}

Finder get codeField => find.widgetWithText(TextField, 'Código');
Finder get labelField => find.widgetWithText(TextField, 'Nome do aparelho');

String fieldText(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

/// The primary action, whose label gives way to progress while pending.
FilledButton vincular(WidgetTester tester) => tester.widget<FilledButton>(
  find.descendant(
    of: find.byType(PrimaryButton),
    matching: find.byType(FilledButton),
  ),
);

/// Types [code] and [label] and presses "Vincular", without settling.
Future<void> link(
  WidgetTester tester, {
  String code = 'ABCD1234',
  String label = 'Tablet da Lia',
}) async {
  if (code.isNotEmpty) await tester.enterText(codeField, code);
  await tester.enterText(labelField, label);
  await tester.pump();
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Vincular'));
  await tester.tap(find.widgetWithText(FilledButton, 'Vincular'));
  await tester.pump();
}

Map<String, dynamic> sent(Harness h) => jsonDecode(
  h.actions
      .singleWhere((a) => a.startsWith('POST /v1/devices/redeem'))
      .substring('POST /v1/devices/redeem '.length),
);

void main() {
  testWidgets('says what linking does, with the code and the device name', (
    tester,
  ) async {
    await redeem(tester);

    expect(find.byType(RedeemScreen), findsOneWidget);
    expect(find.byType(FieldLayout), findsOneWidget);
    expect(find.text('Vincular este aparelho'), findsOneWidget);
    expect(find.textContaining('só abre o modo criança'), findsOneWidget);
    expect(codeField, findsOneWidget);
    expect(labelField, findsOneWidget);
    expect(find.text('Ex.: Tablet da Ana'), findsOneWidget);
    expect(vincular(tester).onPressed, isNull, reason: 'nothing typed yet');
  });

  testWidgets('both fields guide alike: their texts start on one line, '
      'each beside a module that fills once its condition holds', (
    tester,
  ) async {
    await redeem(tester);

    final code = find.text(codeGuidance);
    final label = find.text(deviceLabelGuidance);
    expect(tester.getRect(code).left, tester.getRect(label).left);
    bool met(Finder text) => tester
        .widget<Guidance>(
          find.ancestor(of: text, matching: find.byType(Guidance)),
        )
        .met;
    expect((met(code), met(label)), (false, false));

    await tester.enterText(codeField, 'abcd123');
    await tester.pump();
    expect(met(code), isFalse);
    await tester.enterText(codeField, 'abcd1234');
    await tester.pump();
    expect(met(code), isTrue);
    expect(strandable.hasMatch(codeGuidance), isFalse);
    expect(strandable.hasMatch(deviceLabelGuidance), isFalse);
  });

  testWidgets('the code of the link fills the field, which shows it in two '
      'groups of four, and leaves the location', (tester) async {
    final h = await redeem(
      tester,
      initial: '/vincular-aparelho?codigo=abcd1234',
    );

    expect(fieldText(tester, codeField), 'ABCD-1234');
    expect(h.location(tester), '/vincular-aparelho');
  });

  testWidgets('the code field takes lower case, spaces and hyphens and '
      'groups the characters', (tester) async {
    await redeem(tester);

    for (final (typed, shown) in [
      ('abcd', 'ABCD'),
      ('abcd1', 'ABCD-1'),
      ('ab cd-12 34', 'ABCD-1234'),
      ('abcd-1234-zz', 'ABCD-1234'),
      ('a.b,c', 'ABC'),
    ]) {
      await tester.enterText(codeField, typed);
      await tester.pump();
      expect(fieldText(tester, codeField), shown, reason: typed);
    }
  });

  testWidgets('"Vincular" sends the code as shown and the trimmed name, and '
      'the device enters its child\'s home as the band grows', (tester) async {
    final devices = MemoryDeviceCredentialStore();
    final h = await redeem(tester, devices: devices);

    await link(tester, code: 'abcd 1234', label: '  Tablet da Lia ');
    await pumpUntil(tester, () => h.services.appMode.mode is LinkedDevice);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(sent(h), {'code': 'ABCD-1234', 'label': 'Tablet da Lia'});
    expect(devices.token, 'dev-token');
    expect(h.services.appMode.mode, const LinkedDevice('m1'));
    expect(
      find.byWidgetPredicate(
        (w) => w is BandTransition && w.motion == BandMotion.grow,
      ),
      findsOneWidget,
      reason: 'the ink grows into the child\'s screen',
    );

    await tester.pumpAndSettle();
    expect(h.location(tester), '/crianca');
    expect(find.byType(KidHomeScreen), findsOneWidget);
    expect(find.text('Lia'), findsOneWidget);
  });

  group('the device name', () {
    for (final (name, label) in [
      ('blank', '   '),
      ('41 characters', 'a' * 41),
    ]) {
      testWidgets('$name keeps "Vincular" disabled', (tester) async {
        await redeem(tester);

        await tester.enterText(codeField, 'ABCD1234');
        await tester.enterText(labelField, label);
        await tester.pump();

        expect(vincular(tester).onPressed, isNull);
      });
    }

    testWidgets('40 characters after trimming is enough', (tester) async {
      await redeem(tester);

      await tester.enterText(codeField, 'ABCD1234');
      await tester.enterText(labelField, ' ${'a' * 40} ');
      await tester.pump();

      expect(vincular(tester).onPressed, isNotNull);
    });

    testWidgets('a control character is refused on the field', (tester) async {
      await redeem(tester);

      await tester.enterText(codeField, 'ABCD1234');
      await tester.enterText(labelField, 'Tablet\u0007 da Lia');
      await tester.pump();

      expect(vincular(tester).onPressed, isNull);
      final decoration = tester.widget<TextField>(labelField).decoration!;
      expect(decoration.errorText, isNotNull);
    });

    testWidgets('an incomplete code keeps "Vincular" disabled', (tester) async {
      await redeem(tester);

      await tester.enterText(codeField, 'ABCD123');
      await tester.enterText(labelField, 'Tablet');
      await tester.pump();

      expect(vincular(tester).onPressed, isNull);
    });
  });

  group('a refused redemption keeps what was typed', () {
    for (final (code, status, words) in [
      ('invalid_token', 400, Copy.linkCodeGone),
      ('limit_reached', 409, Copy.devicesFull),
      ('unavailable', 503, Copy.genericRetry),
    ]) {
      testWidgets(code, (tester) async {
        final h = await redeem(tester, answer: (_) => problem(status, code));

        await link(tester);
        await tester.pumpAndSettle();

        expect(find.widgetWithText(ErrorNote, words), findsOneWidget);
        expect(fieldText(tester, codeField), 'ABCD-1234');
        expect(fieldText(tester, labelField), 'Tablet da Lia');
        expect(h.location(tester), '/vincular-aparelho');
        expect(h.services.appMode.mode, const Guardian());
      });
    }

    testWidgets('validation marks the name field', (tester) async {
      await redeem(tester, answer: (_) => problem(422, 'validation'));

      await link(tester);
      await tester.pumpAndSettle();

      final decoration = tester.widget<TextField>(labelField).decoration!;
      expect(decoration.errorText, isNotNull);
      expect(find.byType(ErrorNote), findsNothing);
      expect(fieldText(tester, labelField), 'Tablet da Lia');

      await tester.enterText(labelField, 'Tablet');
      await tester.pump();
      expect(
        tester.widget<TextField>(labelField).decoration!.errorText,
        isNull,
      );
    });

    testWidgets('rate_limited counts the time left down with "Vincular" '
        'disabled', (tester) async {
      await redeem(
        tester,
        answer: (_) =>
            problem(429, 'rate_limited', headers: {'retry-after': '30'}),
      );

      await link(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('30 s'), findsOneWidget);
      expect(vincular(tester).onPressed, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('29 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 29));
      expect(vincular(tester).onPressed, isNotNull);
      expect(fieldText(tester, codeField), 'ABCD-1234');
    });
  });

  testWidgets('"Vincular" waits while the redemption is pending', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    await redeem(tester, answer: (_) => gate.future);

    await link(tester);
    await tester.pump(const Duration(milliseconds: 10));

    expect(vincular(tester).onPressed, isNull);
    gate.complete(problem(503, 'internal'));
    await tester.pumpAndSettle();
    expect(vincular(tester).onPressed, isNotNull);
  });

  testWidgets('the back control returns to the entry screen', (tester) async {
    final h = await redeem(tester);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/entrar');
  });

  testWidgets('a device that holds a guardian session says to sign out '
      'first, and "Sair da conta" does', (tester) async {
    // The router keeps a signed-in device off this route; the
    // screen still refuses one that signed in while it was open.
    final h = Harness(
      kind: ClientKind.mobile,
      signedIn: true,
      devices: MemoryDeviceCredentialStore(),
    );
    h.services.client.status.value = AuthStatus.signedIn;
    expect(h.services.client.status.value, AuthStatus.signedIn);
    final router = GoRouter(
      initialLocation: '/vincular-aparelho',
      routes: [
        GoRoute(
          path: '/vincular-aparelho',
          builder: (_, _) => const RedeemScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      AppScope(
        services: h.services,
        child: MaterialApp.router(
          theme: buildTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );

    await link(tester);
    await tester.pumpAndSettle();

    expect(h.actions, isNot(contains(startsWith('POST /v1/devices'))));
    expect(find.textContaining('Saia da conta antes'), findsOneWidget);
    expect(fieldText(tester, labelField), 'Tablet da Lia');

    await tapOn(tester, find.widgetWithText(QuietAction, 'Sair da conta'));

    expect(h.actions, contains('DELETE /v1/session'));
    expect(h.services.client.status.value, AuthStatus.signedOut);
    expect(find.textContaining('Saia da conta antes'), findsNothing);
    expect(find.text('Sair da conta'), findsNothing);
  });
}

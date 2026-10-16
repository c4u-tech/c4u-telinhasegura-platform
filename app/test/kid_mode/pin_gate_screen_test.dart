import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/pin_pad.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/kid_mode/pin_gate_screen.dart';
import 'package:telinha_segura/parental/app_mode.dart';
import 'package:telinha_segura/parental/kid_mode_mark.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'hand_over_screen_test.dart' show pumpUntil;
import 'set_pin_screen_test.dart'
    show enter, expectNoteAbovePad, modules, padEnabled, type;

/// `/pin` after a sign-in on a device that was in kid mode; the PIN check
/// answers [answer] (204 by default).
Future<Harness> pinGate(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? answer,
}) async {
  late final Harness h;
  h = Harness(
    signedIn: true,
    kidModeMark: MemoryKidModeMark({'a'}),
    api: (req) {
      if (req.url.path == '/v1/parental/pin/verify') {
        return answer?.call(req) ?? http.Response('', 204);
      }
      if (req.method == 'DELETE' && req.url.path == '/v1/session') {
        h.signedIn = false;
      }
      return http.Response('', 204);
    },
  )..family = ownerFamily;
  await h.pump(tester, initial: '/pin');
  return h;
}

void main() {
  testWidgets('says this device was in kid mode and asks for the PIN, with '
      'Sair da conta at the foot', (tester) async {
    final h = await pinGate(tester);

    expect(h.services.appMode.mode, const PinRequired());
    expect(find.byType(PinGateScreen), findsOneWidget);
    expect(find.byType(FieldLayout), findsOneWidget);
    expect(find.text('Digite o PIN dos pais'), findsOneWidget);
    expect(find.textContaining('estava no modo criança'), findsOneWidget);
    expect(find.byType(PinPad), findsOneWidget);
    final foot = find.widgetWithText(QuietAction, 'Sair da conta');
    expect(foot, findsOneWidget);
    expect(
      tester.getRect(foot).top,
      greaterThan(tester.getRect(find.byType(PinPad)).bottom),
    );
  });

  testWidgets('the PIN lands on the family home', (tester) async {
    final h = await pinGate(tester);

    await enter(tester, '2580');

    expect(h.actions, ['POST /v1/parental/pin/verify {"pin":"2580"}']);
    expect(h.services.appMode.mode, const Guardian());
    expect(h.location(tester), '/');
    expect(find.byType(FamilyHomeScreen), findsOneWidget);
  });

  testWidgets('a wrong PIN says so, empties the modules and keeps the pad', (
    tester,
  ) async {
    final h = await pinGate(tester, answer: (_) => problem(403, 'invalid_pin'));

    await enter(tester, '1111');

    expect(find.text('PIN errado. Tente de novo.'), findsOneWidget);
    expect(find.byType(ErrorNote), findsOneWidget);
    expectNoteAbovePad(tester, find.textContaining('estava no modo criança'));
    expect(modules(tester), List.filled(6, false));
    expect(padEnabled(tester), isTrue);
    expect(h.services.appMode.mode, const PinRequired());
    expect(h.location(tester), '/pin');
  });

  testWidgets('rate_limited disables the pad while the time left counts '
      'down', (tester) async {
    await pinGate(
      tester,
      answer: (_) =>
          problem(429, 'rate_limited', headers: {'retry-after': '30'}),
    );

    await type(tester, '1111');
    await tester.tap(find.bySemanticsLabel('Confirmar'));
    await pumpUntil(
      tester,
      () => find.textContaining('Muitas tentativas').evaluate().isNotEmpty,
    );

    expect(find.textContaining('30 s'), findsOneWidget);
    expect(padEnabled(tester), isFalse);
    expect(modules(tester), List.filled(6, false));
    await tester.pump(const Duration(seconds: 30));
    expect(padEnabled(tester), isTrue);
  });

  testWidgets('Sair da conta signs out to the entry screen', (tester) async {
    final h = await pinGate(tester);

    await tester.ensureVisible(find.text('Sair da conta'));
    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();

    expect(h.actions, ['DELETE /v1/session']);
    expect(h.services.client.status.value, AuthStatus.signedOut);
    expect(h.location(tester), '/entrar');
  });
}

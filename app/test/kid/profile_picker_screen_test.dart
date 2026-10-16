import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/kid/kid_layout.dart';
import 'package:telinha_segura/kid/profile_picker_screen.dart';
import 'package:telinha_segura/kid_mode/hand_over_screen.dart';
import 'package:telinha_segura/parental/app_mode.dart';

import '../access/harness.dart';
import '../parental/fakes.dart';
import '../kid_mode/hand_over_screen_test.dart'
    show chosen, choice, pumpUntil, tapOn;
import '../kid_mode/set_pin_screen_test.dart' show modules, padEnabled;
import 'kid_exit_screen_test.dart' show expectCentredBack, submit;

const lia = {'id': 'm1', 'nickname': 'Lia', 'avatar': 'fox', 'age_band': '5-8'};
const teo = {'id': 'm2', 'nickname': 'Téo', 'avatar': 'owl', 'age_band': '2-4'};

/// A child's linked device, bound to Lia, at `/crianca/sair`. The PIN
/// check answers [profiles] (the family's children by default); the
/// re-bind answers [rebind] (the chosen child by default).
Future<Harness> linkedExit(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? profiles,
  FutureOr<http.Response> Function(http.Request)? rebind,
  String initial = '/crianca/sair',
  Size size = const Size(390, 844),
}) async {
  var bound = lia;
  final h = Harness(
    kind: ClientKind.mobile,
    devices: MemoryDeviceCredentialStore('dev'),
    api: (req) {
      switch ((req.method, req.url.path)) {
        case ('POST', '/v1/child/profiles'):
          return profiles?.call(req) ??
              json(200, {
                'profiles': [lia, teo],
              });
        case ('PUT', '/v1/child/profile'):
          if (rebind != null) return rebind(req);
          final id = (jsonDecode(req.body) as Map)['minor_id'];
          bound = id == 'm2' ? teo : lia;
          return json(200, bound);
        case ('GET', '/v1/child/profile'):
          return json(200, bound);
      }
      return http.Response('', 204);
    },
  );
  await h.pump(tester, initial: initial, size: size);
  return h;
}

GoRouter router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first));

/// Gives the PIN on the exit gate and settles on the picker.
Future<void> toPicker(WidgetTester tester, [String pin = '2580']) async {
  await submit(tester, pin);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('on a linked device the PIN opens the picker with the '
      'family\'s children, the current one chosen', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await linkedExit(tester);
    expect(h.services.appMode.mode, const LinkedDevice('m1'));

    await toPicker(tester);

    expect(h.actions, contains('POST /v1/child/profiles {"pin":"2580"}'));
    expect(h.location(tester), '/crianca/quem');
    expect(find.byType(ProfilePickerScreen), findsOneWidget);
    expect(find.byType(KidLayout), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Quem vai assistir?')),
      isSemantics(label: 'Quem vai assistir?', isHeader: true),
    );
    expect(find.byType(ChildChoice), findsNWidgets(2));
    expect(tester.getSemantics(choice('Lia')), chosen('Lia', true));
    expect(tester.getSemantics(choice('Téo')), chosen('Téo', false));
    semantics.dispose();
  });

  testWidgets('the PIN is held in memory only, never in the location', (
    tester,
  ) async {
    final h = await linkedExit(tester);

    await toPicker(tester);

    expect(h.location(tester), isNot(contains('2580')));
    expect(h.services.profilePick?.pin, '2580');
  });

  testWidgets('choosing a child re-binds the device behind the PIN and '
      'lands on that child\'s home; the PIN is dropped', (tester) async {
    final h = await linkedExit(tester);
    await toPicker(tester);

    await tapOn(tester, choice('Téo'));

    expect(
      h.actions,
      contains('PUT /v1/child/profile {"pin":"2580","minor_id":"m2"}'),
    );
    expect(h.services.appMode.mode, const LinkedDevice('m2'));
    expect(h.location(tester), '/crianca');
    expect(find.byType(KidHomeScreen), findsOneWidget);
    expect(find.text('Téo'), findsOneWidget);
    expect(h.services.profilePick, isNull);
  });

  testWidgets('"Voltar" returns to /crianca and drops the PIN', (tester) async {
    final h = await linkedExit(tester);
    await toPicker(tester);

    await tapOn(tester, find.text('Voltar'));

    expect(h.location(tester), '/crianca');
    expect(h.services.profilePick, isNull);
    expect(h.actions, isNot(contains(startsWith('PUT'))));
    expect(h.services.appMode.mode, const LinkedDevice('m1'));
  });

  testWidgets('without a PIN (a reload, a typed path) the picker sends to '
      'the exit gate', (tester) async {
    final h = await linkedExit(tester, initial: '/crianca/quem');

    expect(h.location(tester), '/crianca/sair');
    expect(find.byType(ProfilePickerScreen), findsNothing);
  });

  testWidgets('once left, the picker cannot be reopened without the PIN', (
    tester,
  ) async {
    final h = await linkedExit(tester);
    await toPicker(tester);
    await tapOn(tester, find.text('Voltar'));

    router(tester).go('/crianca/quem');
    await tester.pumpAndSettle();

    expect(h.location(tester), '/crianca/sair');
  });

  testWidgets('a wrong PIN says so, empties the modules and keeps the pad', (
    tester,
  ) async {
    final h = await linkedExit(
      tester,
      profiles: (_) => problem(403, 'invalid_pin'),
    );

    await toPicker(tester, '1111');

    expect(find.text('PIN errado. Tente de novo.'), findsOneWidget);
    expect(modules(tester), List.filled(6, false));
    expect(padEnabled(tester), isTrue);
    expect(h.location(tester), '/crianca/sair');
    expect(h.services.profilePick, isNull);
  });

  testWidgets('rate_limited disables the pad while the time left counts '
      'down', (tester) async {
    await linkedExit(
      tester,
      profiles: (_) =>
          problem(429, 'rate_limited', headers: {'retry-after': '30'}),
    );

    await submit(tester, '1111');
    await pumpUntil(
      tester,
      () => find.textContaining('Muitas tentativas').evaluate().isNotEmpty,
    );

    expect(find.textContaining('30 s'), findsOneWidget);
    expect(padEnabled(tester), isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(padEnabled(tester), isTrue);
  });

  testWidgets('a device unlinked meanwhile (401) leaves kid mode for the '
      'entry screen', (tester) async {
    final h = await linkedExit(
      tester,
      profiles: (_) => problem(401, 'unauthenticated'),
    );

    await toPicker(tester);

    expect(h.services.appMode.mode, const Guardian());
    expect(await h.services.child.isLinked(), isFalse);
    expect(h.location(tester), '/entrar');
    expect(find.byType(EntryScreen), findsOneWidget);
  });

  testWidgets('a re-bind answering 401 leaves the picker for the entry '
      'screen too', (tester) async {
    final h = await linkedExit(
      tester,
      rebind: (_) => problem(401, 'unauthenticated'),
    );
    await toPicker(tester);

    await tapOn(tester, choice('Téo'));

    expect(h.services.appMode.mode, const Guardian());
    expect(h.location(tester), '/entrar');
    expect(h.services.profilePick, isNull);
  });

  testWidgets('a refused re-bind says why and keeps the picker', (
    tester,
  ) async {
    final h = await linkedExit(tester, rebind: (_) => problem(503, 'internal'));
    await toPicker(tester);

    await tapOn(tester, choice('Téo'));

    expect(find.byType(ErrorNote), findsOneWidget);
    expect(h.location(tester), '/crianca/quem');
    expect(h.services.appMode.mode, const LinkedDevice('m1'));
  });

  group('the picker\'s rows stay balanced, the labels on one line', () {
    final four = [
      lia,
      teo,
      {'id': 'm3', 'nickname': 'Nina', 'avatar': 'cat', 'age_band': '5-8'},
      {'id': 'm4', 'nickname': 'Davi', 'avatar': 'turtle', 'age_band': '2-4'},
    ];
    for (final size in [const Size(390, 844), const Size(1440, 900)]) {
      testWidgets('four children at ${size.width.toInt()} px', (tester) async {
        await linkedExit(
          tester,
          size: size,
          profiles: (_) => json(200, {'profiles': four}),
        );
        await toPicker(tester);

        // Children whose labels share a baseline share a row.
        final rows = <double, List<Rect>>{};
        for (final child in four) {
          final label = tester.getRect(find.text(child['nickname']!));
          rows.putIfAbsent(label.bottom, () => []).add(label);
        }
        final counts = [for (final row in rows.values) row.length];
        expect(counts.reduce(math.max) - counts.reduce(math.min), 0);
        expect(counts.length, lessThanOrEqualTo(2));
        // Every row centred on the screen.
        for (final row in rows.values) {
          final left = row.map((r) => r.left).reduce(math.min);
          final right = row.map((r) => r.right).reduce(math.max);
          expect((left + right) / 2, closeTo(size.width / 2, 1));
        }
        // Avatars of one row on one line too.
        final discs = [
          for (final choice in tester.widgetList<ChildChoice>(
            find.byType(ChildChoice),
          ))
            tester.getRect(
              find.descendant(
                of: find.byWidget(choice),
                matching: find.byType(AvatarDisc),
              ),
            ),
        ];
        expect(discs.map((r) => r.top).toSet(), hasLength(counts.length));
      });
    }
  });

  testWidgets('the heading and "Voltar" are centred, as the grid is', (
    tester,
  ) async {
    await linkedExit(tester);
    await toPicker(tester);

    expect(
      tester.widget<Text>(find.text('Quem vai assistir?')).textAlign,
      TextAlign.center,
    );
    expectCentredBack(tester, 390);
  });
}

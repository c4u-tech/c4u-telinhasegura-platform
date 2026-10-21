import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/entry_screen.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/family/family_home_screen.dart';
import 'package:telinha_segura/kid/kid_home_screen.dart';
import 'package:telinha_segura/kid_mode/pin_gate_screen.dart';
import 'package:telinha_segura/kid_mode/redeem_screen.dart';
import 'package:telinha_segura/parental/app_mode.dart';
import 'package:telinha_segura/parental/kid_mode_mark.dart';
import 'package:telinha_segura/shell/splash.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import '../parental/fakes.dart';
import '../parental/parental_api_test.dart' show profileJson;

GoRouter router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first));

const guardianScreens = [
  '/',
  '/familia/criancas',
  '/familia/responsaveis',
  // The screen-time screens.
  '/familia/tempo',
  '/familia/tempo/m1',
  '/familia/tempo/m1/mais',
  '/familia/tempo/m1/limite',
  '/modo-crianca',
  '/modo-crianca/pin',
  '/modo-crianca/entregar',
  '/modo-crianca/vincular',
  '/modo-crianca/aparelhos',
  '/conta',
  '/conta/email',
  '/conta/senha',
  '/conta/aparelhos',
  '/conta/dados',
  '/conta/excluir',
  // The second factor, for a platform role holder.
  '/conta/verificacao',
  '/conta/verificacao/ativar',
  // The curation screens, with both roles.
  '/sugestoes',
  '/sugestoes/nova',
  '/curadoria',
  '/curadoria/v1',
  '/curadoria/v1/aprovar',
  '/curadoria/v1/recusar',
  '/admin',
  '/admin/equipe',
  '/admin/equipe/nova',
  '/admin/equipe/a1',
  '/moderacao/retidos',
  '/moderacao/retidos/v1',
  // A pacotinho on a child's catalogue, as a guardian sees it.
  '/familia/videos/m1/pacotinho/k1',
];
const childScreens = [
  '/crianca',
  '/crianca/sair',
  '/crianca/quem',
  // The player; `/crianca/assistir` alone is no
  // video.
  '/crianca/assistir/v1',
  '/crianca/assistir',
];
const signedOutScreens = ['/entrar', '/entrar/email', '/criar-conta'];
const linkScreen = '/vincular-aparelho?codigo=ABCD1234';

/// Every route family the gate decides on.
const everyPath = [
  ...guardianScreens,
  ...childScreens,
  '/pin',
  ...signedOutScreens,
  linkScreen,
  '/convite?token=T',
];

/// A signed-in guardian session locked to a child.
Harness sharedKid() =>
    Harness(signedIn: true, api: childApi)..kidMode = {'minor_id': 'm1'};

/// The child routes' reads: a profile, and a play the server allows, so
/// the player stays where it opened.
http.Response childApi(http.Request req) => switch (req.url.path) {
  '/v1/child/profile' => json(200, profileJson),
  '/v1/child/plays' => json(201, {
    'play_id': 'p1',
    'youtube_id': 'yt1',
    'remaining_seconds': 600,
  }),
  _ => http.Response('', 204),
};

/// A child's own device: a stored device credential and no session.
Harness linkedDevice() => Harness(
  kind: ClientKind.mobile,
  devices: MemoryDeviceCredentialStore('dev'),
  api: childApi,
);

/// A sign-in on a device that was in kid mode.
Harness pinRequired() =>
    Harness(signedIn: true, kidModeMark: MemoryKidModeMark({'a'}));

/// Opens each path and returns where the router left it.
Future<Map<String, String>> landings(
  WidgetTester tester,
  Harness h,
  List<String> paths,
) async {
  final at = <String, String>{};
  for (final path in paths) {
    router(tester).go(path);
    await tester.pumpAndSettle();
    at[path] = h.location(tester);
  }
  return at;
}

void main() {
  group('a null mode shows only the splash', () {
    testWidgets('no route renders until the mode settles after the session', (
      tester,
    ) async {
      final h = Harness(
        signedIn: true,
        sessionDelay: const Duration(seconds: 1),
      )..family = ownerFamily;
      await tester.pumpWidget(h.app());

      // The session restore answered; the mode's read has not.
      await tester.pump(const Duration(seconds: 1));
      expect(h.services.client.status.value, AuthStatus.signedIn);
      expect(h.services.appMode.mode, isNull);
      expect(find.byType(Splash), findsOneWidget);
      expect(find.byType(FamilyHomeScreen), findsNothing);
      expect(find.text('Tentar de novo'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(h.services.appMode.mode, const Guardian());
      expect(find.byType(Splash), findsNothing);
      expect(find.byType(FamilyHomeScreen), findsOneWidget);
      // The home's own reads wait out the same delay.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });

    testWidgets('a failed restore offers "Tentar de novo", which restores '
        'again', (tester) async {
      final h = Harness(kind: ClientKind.mobile, signedIn: true)
        ..sessionFailure = 500
        ..family = ownerFamily;
      await h.pump(tester);

      expect(h.services.appMode.mode, isNull);
      expect(find.byType(Splash), findsOneWidget);
      expect(find.byType(FamilyHomeScreen), findsNothing);

      h.sessionFailure = null;
      await tester.tap(find.widgetWithText(FilledButton, 'Tentar de novo'));
      await tester.pumpAndSettle();

      expect(h.services.appMode.mode, const Guardian());
      expect(find.byType(FamilyHomeScreen), findsOneWidget);
    });

    testWidgets('a retry that fails again keeps the splash and the retry', (
      tester,
    ) async {
      final h = Harness(kind: ClientKind.mobile, signedIn: true)
        ..sessionFailure = 500;
      await h.pump(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Tentar de novo'));
      await tester.pumpAndSettle();

      expect(h.services.appMode.mode, isNull);
      expect(find.widgetWithText(FilledButton, 'Tentar de novo'), findsOne);
    });
  });

  testWidgets('a shared kid reaches only /crianca and /crianca/sair', (
    tester,
  ) async {
    final h = sharedKid();
    await h.pump(tester, initial: '/');
    expect(h.services.appMode.mode, const SharedKid('m1'));
    expect(find.byType(KidHomeScreen), findsOneWidget);

    expect(await landings(tester, h, everyPath), {
      for (final path in everyPath)
        path: switch (path) {
          '/crianca' || '/crianca/sair' || '/crianca/assistir/v1' => path,
          _ => '/crianca',
        },
    });
  });

  testWidgets('a linked device reaches only /crianca, /crianca/sair and '
      '/crianca/quem', (tester) async {
    final h = linkedDevice();
    await h.pump(tester, initial: '/');
    expect(h.services.appMode.mode, const LinkedDevice('m1'));
    expect(find.byType(KidHomeScreen), findsOneWidget);

    expect(await landings(tester, h, everyPath), {
      for (final path in everyPath)
        path: switch (path) {
          // The picker opens only behind the PIN.
          '/crianca/quem' => '/crianca/sair',
          '/crianca/assistir' => '/crianca',
          _ when childScreens.contains(path) => path,
          _ => '/crianca',
        },
    });
  });

  testWidgets('a stored device credential never reaches the entry screen', (
    tester,
  ) async {
    final h = linkedDevice();
    await h.pump(tester, initial: '/entrar');

    expect(find.byType(EntryScreen), findsNothing);
    expect(h.location(tester), '/crianca');
  });

  testWidgets('PinRequired reaches only /pin', (tester) async {
    final h = pinRequired();
    await h.pump(tester, initial: '/');
    expect(h.services.appMode.mode, const PinRequired());
    expect(find.byType(PinGateScreen), findsOneWidget);

    expect(await landings(tester, h, everyPath), {
      for (final path in everyPath) path: '/pin',
    });
  });

  group('a guardian', () {
    testWidgets('signed in: the child routes and /pin go home, the guardian '
        'screens render, the signed-out ones go home', (tester) async {
      final h = Harness(signedIn: true)
        ..family = ownerFamily
        ..roles = ['admin', 'curator'];
      await h.pump(tester, initial: '/');
      expect(h.services.appMode.mode, const Guardian());

      final paths = everyPath.where((p) => !p.startsWith('/convite')).toList();
      expect(await landings(tester, h, paths), {
        for (final path in paths)
          path: guardianScreens.contains(path) ? path : '/',
      });
    });

    testWidgets('signed out: the guardian and child routes and /pin go to '
        '/entrar', (tester) async {
      final h = Harness();
      await h.pump(tester, initial: '/entrar');
      expect(h.services.appMode.mode, const Guardian());

      final paths = [...guardianScreens, ...childScreens, '/pin'];
      expect(await landings(tester, h, paths), {
        for (final path in paths) path: '/entrar',
      });
    });

    testWidgets('without a family, /modo-crianca goes home', (tester) async {
      final h = Harness(signedIn: true)..family = null;
      await h.pump(tester, initial: '/');
      await tester.pumpAndSettle();

      router(tester).go('/modo-crianca');
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
    });
  });

  group('/vincular-aparelho', () {
    testWidgets('signed out on Android or iOS it renders with its code, '
        'which then leaves the location', (tester) async {
      final h = Harness(
        kind: ClientKind.mobile,
        devices: MemoryDeviceCredentialStore(),
      );
      await h.pump(tester, initial: linkScreen);

      expect(find.byType(RedeemScreen), findsOneWidget);
      expect(find.text('ABCD-1234'), findsOneWidget);
      expect(h.location(tester), '/vincular-aparelho');
    });

    testWidgets('on the web it goes to /entrar', (tester) async {
      final h = Harness();
      await h.pump(tester, initial: linkScreen);

      expect(h.location(tester), '/entrar');
    });

    testWidgets('signed in, the deep link follows the gate and drops the '
        'code', (tester) async {
      final h = Harness(
        kind: ClientKind.mobile,
        signedIn: true,
        devices: MemoryDeviceCredentialStore(),
      )..family = ownerFamily;
      await h.pump(tester, initial: linkScreen);

      expect(h.location(tester), '/');
    });

    testWidgets('in kid mode, the deep link lands on /crianca and drops the '
        'code', (tester) async {
      final h = sharedKid();
      await h.pump(tester, initial: linkScreen);

      expect(h.location(tester), '/crianca');
    });
  });

  group('the deep link telinhasegura://vincular?codigo=', () {
    const deepLink = 'telinhasegura://vincular?codigo=ABCD1234';

    testWidgets('signed out on Android or iOS it opens /vincular-aparelho '
        'with the code filled in', (tester) async {
      final h = Harness(
        kind: ClientKind.mobile,
        devices: MemoryDeviceCredentialStore(),
      );
      await h.pump(tester, initial: deepLink);

      expect(find.byType(RedeemScreen), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Código'))
            .controller!
            .text,
        'ABCD-1234',
      );
    });

    testWidgets('arriving while the app runs, it does the same', (
      tester,
    ) async {
      final h = Harness(
        kind: ClientKind.mobile,
        devices: MemoryDeviceCredentialStore(),
      );
      await h.pump(tester, initial: '/entrar');

      router(tester).go(deepLink);
      await tester.pumpAndSettle();

      expect(h.location(tester), '/vincular-aparelho');
      expect(find.text('ABCD-1234'), findsOneWidget);
    });

    testWidgets('signed in, it follows the gate and drops the code', (
      tester,
    ) async {
      final h = Harness(
        kind: ClientKind.mobile,
        signedIn: true,
        devices: MemoryDeviceCredentialStore(),
      )..family = ownerFamily;
      await h.pump(tester, initial: deepLink);

      expect(h.location(tester), '/');
      expect(find.byType(RedeemScreen), findsNothing);
    });

    testWidgets('in kid mode, it lands on /crianca and drops the code', (
      tester,
    ) async {
      for (final h in [sharedKid(), linkedDevice()]) {
        await h.pump(tester, initial: deepLink);

        expect(h.location(tester), '/crianca');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('on the web it goes to /entrar', (tester) async {
      final h = Harness();
      await h.pump(tester, initial: deepLink);

      expect(h.location(tester), '/entrar');
    });
  });

  group('a mode change re-routes at once', () {
    testWidgets('guardian to shared kid and back', (tester) async {
      final h = Harness(signedIn: true)..family = ownerFamily;
      await h.pump(tester, initial: '/familia/responsaveis');

      h.services.appMode.restoreAs(const SharedKid('m1'));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/crianca');

      h.services.appMode.restoreAs(const Guardian());
      await tester.pumpAndSettle();
      expect(h.location(tester), '/');
    });

    testWidgets('PinRequired to guardian leaves /pin for home', (tester) async {
      final h = pinRequired()..family = ownerFamily;
      await h.pump(tester, initial: '/');
      expect(h.location(tester), '/pin');

      h.services.appMode.restoreAs(const Guardian());
      await tester.pumpAndSettle();

      expect(h.location(tester), '/');
    });
  });

  testWidgets('on the web a 401 from a child route signs out and lands on '
      '/entrar without a reload', (tester) async {
    final h = sharedKid()
      ..api = (req) => req.url.path.startsWith('/v1/child/')
          ? problem(401, 'unauthenticated')
          : http.Response('', 204);
    // The child home's own profile read answers 401.
    await h.pump(tester, initial: '/crianca');

    expect(h.calls, contains('GET /v1/child/profile'));
    expect(h.services.client.status.value, AuthStatus.signedOut);
    expect(find.byType(EntryScreen), findsOneWidget);
    expect(h.location(tester), '/entrar');
  });

  testWidgets('a guardian call answering 403 kid_mode resyncs and lands on '
      '/crianca', (tester) async {
    final h = Harness(signedIn: true)..family = ownerFamily;
    await h.pump(tester, initial: '/familia/responsaveis');
    expect(h.services.appMode.mode, const Guardian());

    // Another device's hand-over locked this session.
    h
      ..kidMode = {'minor_id': 'm1'}
      ..api = ((req) => problem(403, 'kid_mode'))
      ..parentalRead = ((req) => problem(403, 'kid_mode'));
    await expectLater(h.services.parental.pinIsSet(), throwsA(anything));
    await tester.pumpAndSettle();

    expect(h.services.appMode.mode, const SharedKid('m1'));
    expect(find.byType(KidHomeScreen), findsOneWidget);
    expect(h.location(tester), '/crianca');
  });
}

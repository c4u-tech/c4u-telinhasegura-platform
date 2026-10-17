import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telinha_segura/auth/device_label.dart';
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/auth/apple_id_tokens.dart';
import 'package:telinha_segura/auth/google_web_sign_in.dart';
import 'package:telinha_segura/auth/provider_authenticator.dart';
import 'package:telinha_segura/auth/provider_sign_in.dart';
import 'package:telinha_segura/auth/token_store.dart';
import 'package:telinha_segura/parental/device_credential_store.dart';
import 'package:telinha_segura/parental/kid_mode_mark.dart';
import 'package:telinha_segura/privacy/export_delivery.dart';
import 'package:telinha_segura/screentime/time_zone_source.dart';
import 'package:telinha_segura/shell/app.dart';
import 'package:telinha_segura/shell/services.dart';

import '../auth/fakes.dart';
import '../kid/fake_player.dart';

export '../auth/fakes.dart' show json, problem;

const signedInBody = {
  'account': {'id': 'a', 'email': 'ana@example.com', 'email_verified': true},
  'session': {'id': 's', 'client': 'web', 'csrf_token': 'c1'},
};

/// Answers the provider sheet per provider; null means "cancelled".
class FakeProviders implements ProviderAuthenticator {
  final answers = <IdentityProvider, String?>{};
  final asked = <IdentityProvider>[];

  @override
  Future<String?> idToken(IdentityProvider provider) async {
    asked.add(provider);
    return answers[provider];
  }

  AppleCredential? apple;
  var appleAsked = 0;

  /// Thrown by [appleCredential] when set, as a failed Apple sheet is.
  Object? appleError;

  /// Held open while set, as the Apple sheet is while it is up.
  Completer<AppleCredential?>? appleSheet;

  @override
  Future<AppleCredential?> appleCredential() async {
    appleAsked++;
    if (appleError case final error?) throw error;
    if (appleSheet case final sheet?) return sheet.future;
    return apple;
  }
}

class FakeGoogleWeb implements GoogleWebSignIn {
  final tokens = StreamController<String>.broadcast();

  @override
  Future<void> get ready => Future.value();

  @override
  Widget button({required double width}) =>
      const SizedBox(key: Key('gis-button'), width: 320, height: 44);

  @override
  Stream<String> idTokens() => tokens.stream;
}

const allProviders = ProviderSettings(
  googleClientId: 'g.apps.googleusercontent.com',
  googleServerClientId: 'g.apps.googleusercontent.com',
  appleServicesId: 'tech.coding4u.telinhasegura.web',
  appleRedirectUri: 'https://app.test',
);

const noProviders = ProviderSettings(
  googleClientId: '',
  googleServerClientId: '',
  appleServicesId: '',
  appleRedirectUri: '',
);

/// One app run against a scripted API. [calls] records each request as
/// "METHOD /path body", the session restore included.
class Harness {
  Harness({
    this.kind = ClientKind.web,
    FutureOr<http.Response> Function(http.Request)? api,
    this.settings = noProviders,
    this.googleWeb,
    bool signedIn = false,
    this.sessionDelay = Duration.zero,
    DeviceCredentialStore? devices,
    KidModeMark? kidModeMark,
    ExportDelivery? exports,
    this.deviceLabel = testDeviceLabel,
    FakeKidPlayer? player,
    FakeKidPlayer? adultPlayer,
    this.timeZone = 'America/Sao_Paulo',
  }) : player = player ?? FakeKidPlayer(),
       adultPlayer = adultPlayer ?? FakeKidPlayer() {
    _api = api ?? (_) => http.Response('', 204);
    final store = MemoryTokenStore();
    if (signedIn && kind == ClientKind.mobile) {
      store.tokens = const Tokens(access: 'a', refresh: 'r');
    }
    final client = ApiClient(
      baseUrl: baseUrl,
      kind: kind,
      tokens: kind == ClientKind.mobile ? store : null,
      httpClient: MockClient((req) async {
        final path = req.url.toString().substring(baseUrl.toString().length);
        calls.add('${req.method} $path ${req.body}'.trimRight());
        if (req.method == 'GET' && req.url.path == '/v1/session') {
          // A zero delay would still be a timer, which pumpAndSettle does
          // not wait for when no frame is scheduled (a refresh's session
          // read behind an unchanged screen).
          if (sessionDelay > Duration.zero) {
            await Future<void>.delayed(sessionDelay);
          }
          return session(req);
        }
        if (req.method == 'GET' && req.url.path == '/v1/family') {
          return (familyRead ?? _family)();
        }
        if (req.method == 'GET' && _parentalReads.contains(req.url.path)) {
          return (parentalRead ?? _parental)(req);
        }
        return _api(req);
      }),
    );
    services = AppServices(
      client: client,
      providers: providers,
      settings: settings,
      googleWeb: googleWeb,
      devices: devices,
      kidModeMark: kidModeMark,
      // A fixed label, so no test reaches the device_info plugin.
      deviceLabel: FixedDeviceLabel(deviceLabel),
      // No platform channel for the zone a screen-time save sends.
      timeZone: FixedTimeZone(timeZone),
      // No WebView in a widget test.
      player: this.player,
      adultPlayer: this.adultPlayer,
      links: links,
      // A download that always lands, so no test reaches a plugin.
      exports:
          exports ??
          PlatformExportDelivery(
            web: true,
            download: (_, {origin}) async => true,
          ),
    );
    _signedIn = signedIn;
  }

  final ClientKind kind;

  /// The device's IANA zone.
  final String timeZone;

  /// The embedded player the kid screens open.
  final FakeKidPlayer player;

  /// The embedded player the curator's and admin's screens open.
  final FakeKidPlayer adultPlayer;

  /// What the app opened outside itself.
  final links = FakeLinks();

  /// The label this device's sign-ins send.
  final String deviceLabel;
  final Duration sessionDelay;
  final ProviderSettings settings;
  final GoogleWebSignIn? googleWeb;
  final providers = FakeProviders();
  final calls = <String>[];
  late final AppServices services;
  late FutureOr<http.Response> Function(http.Request) _api;
  late bool _signedIn;

  /// The account read answers with an unverified email.
  bool unverified = false;

  /// The account's email in the account read.
  String email = 'ana@example.com';

  /// The session's platform roles (`admin`, `curator`), as the wire
  /// names them.
  List<String> roles = const [];

  /// The account's standing in the account read (`active`, `suspended`).
  String status = 'active';

  /// The session's kid-mode lock (`{'minor_id': ...}`); null when unlocked.
  Map<String, Object?>? kidMode;

  /// When set, `GET /v1/session` answers this status as a problem.
  int? sessionFailure;

  /// `GET /v1/session`, the restore and the home screen's account read.
  http.Response session(http.Request _) {
    if (sessionFailure case final status?) return problem(status, 'internal');
    if (!_signedIn) return problem(401, 'unauthenticated');
    final account = signedInBody['account']!;
    return json(200, {
      ...signedInBody,
      'account': {
        ...account,
        'email': email,
        'email_verified': !unverified,
        'status': status,
      },
      'kid_mode': ?kidMode,
      'roles': roles,
    });
  }

  /// The family `GET /v1/family` answers; null answers `no_family`.
  Map<String, Object?>? family;

  /// Replaces the family read (a failure, a delay).
  FutureOr<http.Response> Function()? familyRead;

  http.Response _family() =>
      family == null ? problem(404, 'no_family') : json(200, family!);

  /// Whether `GET /v1/parental/pin` says the family has a PIN.
  bool pinSet = false;

  /// What `GET /v1/parental/devices` lists (wire JSON).
  List<Map<String, Object?>> linkedDevices = [];

  /// Replaces both kid-mode reads (a failure, a delay).
  FutureOr<http.Response> Function(http.Request)? parentalRead;

  static const _parentalReads = {'/v1/parental/pin', '/v1/parental/devices'};

  http.Response _parental(http.Request req) => req.url.path.endsWith('/pin')
      ? json(200, {'set': pinSet})
      : json(200, {'devices': linkedDevices});

  set signedIn(bool v) => _signedIn = v;

  set api(FutureOr<http.Response> Function(http.Request) answer) =>
      _api = answer;

  /// The requests a test cares about: everything but the session, family,
  /// invitations and kid-mode reads.
  List<String> get actions => calls
      .where(
        (c) =>
            !c.startsWith('GET /v1/session') &&
            c != 'GET /v1/family' &&
            c != 'GET /v1/invitations' &&
            !_parentalReads.any((p) => c == 'GET $p'),
      )
      .toList();

  /// The router's current location, query included.
  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .routerDelegate
          .currentConfiguration
          .uri
          .toString();

  Future<void> pump(
    WidgetTester tester, {
    String initial = '/',
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(app(initial: initial));
    await tester.pumpAndSettle();
  }

  Widget app({String initial = '/'}) =>
      TelinhaSeguraApp(services: services, initialLocation: initial);
}

/// A [TimeZoneSource] that answers [name].
class FixedTimeZone implements TimeZoneSource {
  const FixedTimeZone(this.name);

  final String name;

  @override
  Future<String> current() async => name;
}

/// The device label a [Harness] signs in with unless a test says otherwise.
const testDeviceLabel = 'Samsung SM-S911B';

/// A [DeviceLabelSource] that answers [label].
class FixedDeviceLabel implements DeviceLabelSource {
  FixedDeviceLabel(this.label);

  final String label;

  @override
  Future<String> read() async => label;
}

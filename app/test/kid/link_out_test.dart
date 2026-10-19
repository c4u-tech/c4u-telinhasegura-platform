import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart' show ErrorNote;
import 'package:telinha_segura/auth/api_client.dart';
import 'package:telinha_segura/kid/kid_exit_screen.dart';
import 'package:telinha_segura/kid/kid_player.dart';
import 'package:telinha_segura/kid/player_screen.dart';
import 'package:telinha_segura/kid/shelves.dart';
import 'package:telinha_segura/parental/app_mode.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import '../parental/fakes.dart';
import '../parental/parental_api_test.dart' show profileJson;
import 'kid_exit_screen_test.dart' show submit;
import 'kid_shelves_test.dart' show pixel, twoShelves;

final logo = Uri.parse('https://www.youtube.com/watch?v=yt1&feature=emb_logo');

/// The child routes' reads; [pin] answers the PIN on either device.
FutureOr<http.Response> Function(http.Request) childApi(
  Harness Function() harness, {
  FutureOr<http.Response> Function(http.Request)? pin,
}) => (req) {
  final path = req.url.path;
  if (path == '/v1/child/profile') return json(200, profileJson);
  if (path == '/v1/child/catalog') return json(200, twoShelves);
  if (path.startsWith('/v1/child/thumbs/')) {
    return http.Response.bytes(pixel, 200);
  }
  if (path == '/v1/child/plays') {
    return json(201, {
      'play_id': 'p1',
      'youtube_id': 'yt1',
      'remaining_seconds': 600,
    });
  }
  if (path == '/v1/child/unlock') {
    if (pin != null) return pin(req);
    harness().kidMode = null;
    return http.Response('', 204);
  }
  if (path == '/v1/child/profiles') {
    if (pin != null) return pin(req);
    return json(200, {
      'profiles': [profileJson],
    });
  }
  return http.Response('', 204);
};

/// A shared kid playing v1 whose player asked to leave for [logo].
Future<Harness> leavingShared(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? pin,
  Uri? to,
}) async {
  late final Harness h;
  h = Harness(signedIn: true, api: childApi(() => h, pin: pin))
    ..kidMode = {'minor_id': 'm1'}
    ..family = ownerFamily;
  await h.pump(tester, initial: '/crianca');
  return _leave(tester, h, to: to);
}

/// A linked device playing v1 whose player asked to leave for [logo].
Future<Harness> leavingLinked(WidgetTester tester) async {
  late final Harness h;
  h = Harness(
    kind: ClientKind.mobile,
    devices: MemoryDeviceCredentialStore('dev'),
    api: childApi(() => h),
  );
  await h.pump(tester, initial: '/crianca');
  return _leave(tester, h);
}

Future<Harness> _leave(WidgetTester tester, Harness h, {Uri? to}) async {
  await tester.tap(find.byType(VideoTile).first);
  await tester.pumpAndSettle();
  h.player.current!.emit(PlayerLeaving(to ?? logo));
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('a suggested video on the end screen opens the PIN gate, '
      'never the video', (tester) async {
    final h = await leavingShared(
      tester,
      to: Uri.parse('https://m.youtube.com/watch?v=other&feature=emb_rel_end'),
    );

    expect(h.player.current!.calls, contains('pause'));
    expect(find.byType(KidExitScreen), findsOneWidget);
    expect(h.links.opened, isEmpty);
  });

  testWidgets('a link out pauses the video and opens the PIN gate, the link '
      'held in memory only', (tester) async {
    final h = await leavingShared(tester);

    expect(h.player.current!.calls, contains('pause'));
    expect(h.player.current!.closed, isFalse);
    // The gate stands over the paused video; the link is in no route.
    expect(find.byType(KidExitScreen), findsOneWidget);
    expect(h.location(tester), '/crianca/assistir/v1');
    expect(h.links.opened, isEmpty);
  });

  testWidgets('on a shared device the PIN ends kid mode, then the link opens '
      'outside', (tester) async {
    final h = await leavingShared(tester);

    await submit(tester, '1234');
    await tester.pumpAndSettle();

    expect(h.actions, contains('POST /v1/child/unlock {"pin":"1234"}'));
    expect(h.services.appMode.mode, const Guardian());
    expect(h.links.opened, [logo]);
    expect(h.location(tester), '/');
    expect(h.player.current!.closed, isTrue);
  });

  testWidgets('on a linked device the PIN is checked, the link opens and the '
      'video waits, still in kid mode', (tester) async {
    final h = await leavingLinked(tester);

    await submit(tester, '1234');
    await tester.pumpAndSettle();

    expect(h.actions, contains('POST /v1/child/profiles {"pin":"1234"}'));
    expect(h.links.opened, [logo]);
    expect(h.services.appMode.mode, const LinkedDevice('m1'));
    expect(h.location(tester), '/crianca/assistir/v1');
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(h.player.opened, hasLength(1));
    expect(h.player.current!.closed, isFalse);
  });

  testWidgets('"Voltar" goes back to the video without the link', (
    tester,
  ) async {
    final h = await leavingShared(tester);

    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/crianca/assistir/v1');
    expect(h.links.opened, isEmpty);
    expect(h.player.opened, hasLength(1));
    expect(h.player.current!.closed, isFalse);
    // The link is forgotten: the next exit is an ordinary one.
    expect(h.services.linkErrand, isNull);
  });

  testWidgets('a wrong PIN says so and opens nothing', (tester) async {
    final h = await leavingShared(
      tester,
      pin: (_) => problem(403, 'invalid_pin'),
    );

    await submit(tester, '1111');
    await tester.pumpAndSettle();

    expect(find.byType(ErrorNote), findsOneWidget);
    expect(h.links.opened, isEmpty);
    expect(find.byType(KidExitScreen), findsOneWidget);
    expect(h.services.appMode.mode, const SharedKid('m1'));
  });
}

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/kid_mode/devices_screen.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'hand_over_screen_test.dart' show tapOn;

/// A linked device as the server lists it, last used [daysAgo] days
/// before the test's clock.
Map<String, Object?> device(
  String id,
  String label,
  String minorId, {
  int daysAgo = 0,
}) {
  final seen = clock.now().subtract(Duration(days: daysAgo)).toUtc();
  return {
    'id': id,
    'label': label,
    'minor_id': minorId,
    'linked_at': seen.toIso8601String(),
    'last_seen_at': seen.toIso8601String(),
  };
}

/// `/modo-crianca/aparelhos` for a family with Lia and Téo, listing
/// [devices]; an unlink answers [unlink] (204 by default, the device
/// then gone from the list).
Future<Harness> devicesScreen(
  WidgetTester tester, {
  List<Map<String, Object?>> Function()? devices,
  FutureOr<http.Response> Function(http.Request)? unlink,
  FutureOr<http.Response> Function(http.Request)? read,
}) async {
  late final Harness h;
  h =
      Harness(
          signedIn: true,
          api: (req) {
            if (req.method == 'DELETE') {
              if (unlink != null) return unlink(req);
              final id = req.url.pathSegments.last;
              h.linkedDevices = [
                for (final d in h.linkedDevices)
                  if (d['id'] != id) d,
              ];
              return http.Response('', 204);
            }
            return http.Response('', 204);
          },
        )
        ..family = familyWith([
          minorJson('m1', 'Lia'),
          minorJson('m2', 'Téo', avatar: 'owl'),
        ])
        ..pinSet = true
        ..parentalRead = read;
  h.linkedDevices =
      devices?.call() ??
      [
        device('d1', 'Tablet da Lia', 'm1'),
        device('d2', 'Celular antigo', 'gone', daysAgo: 2),
      ];
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: '/modo-crianca/aparelhos');
  return h;
}

Finder get unlinkActions => find.widgetWithText(QuietAction, 'Desvincular');

void main() {
  testWidgets('each device with its label, its child, when it was last '
      'used, and the capacity row; no chevron', (tester) async {
    final semantics = tester.ensureSemantics();
    await devicesScreen(tester);

    expect(find.byType(DevicesScreen), findsOneWidget);
    expect(find.text('Aparelhos vinculados'), findsOneWidget);
    expect(find.text('Tablet da Lia'), findsOneWidget);
    expect(find.text('Celular antigo'), findsOneWidget);
    expect(find.text('Lia · usado hoje'), findsOneWidget);
    expect(find.text('usado há 2 dias'), findsOneWidget);
    // The unknown child: the neutral avatar, no nickname.
    final avatars = tester
        .widgetList<AvatarDisc>(find.byType(AvatarDisc))
        .map((a) => (a.avatar, a.size));
    expect(avatars, [(Avatar.fox, 40.0), (Avatar.unknown, 40.0)]);
    expect(find.textContaining('Téo'), findsNothing);
    expect(
      tester.widget<CapacityRow>(find.byType(CapacityRow)).words,
      '2 de 10 aparelhos',
    );
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(unlinkActions, findsNWidgets(2));
    expect(
      find.bySemanticsLabel('Tablet da Lia, de Lia, usado hoje'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Celular antigo, usado há 2 dias'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('Desvincular asks first, naming the device and the child, '
      'and Cancelar keeps it', (tester) async {
    final h = await devicesScreen(tester);

    await tapOn(tester, unlinkActions.first);

    expect(find.byType(DestructiveConfirmation), findsOneWidget);
    expect(find.text('Desvincular Tablet da Lia?'), findsOneWidget);
    expect(
      find.textContaining('Tablet da Lia deixa de ser o aparelho de Lia'),
      findsOneWidget,
    );
    expect(
      find.textContaining('sai do modo criança na próxima vez'),
      findsOneWidget,
    );
    await tapOn(tester, find.text('Cancelar'));

    expect(find.byType(DestructiveConfirmation), findsNothing);
    expect(h.actions, isEmpty);
    expect(find.text('Tablet da Lia'), findsOneWidget);
  });

  testWidgets('confirming unlinks the device and refreshes the list', (
    tester,
  ) async {
    final h = await devicesScreen(tester);

    await tapOn(tester, unlinkActions.first);
    await tapOn(
      tester,
      find.descendant(
        of: find.byType(DestructiveConfirmation),
        matching: find.widgetWithText(PrimaryButton, 'Desvincular'),
      ),
    );

    expect(h.actions, ['DELETE /v1/parental/devices/d1']);
    expect(find.text('Tablet da Lia'), findsNothing);
    expect(find.text('Celular antigo'), findsOneWidget);
    expect(find.text('Desvinculamos Tablet da Lia.'), findsOneWidget);
    expect(
      tester.widget<CapacityRow>(find.byType(CapacityRow)).words,
      '1 de 10 aparelhos',
    );
  });

  testWidgets('a device already gone refreshes the list with a calm notice', (
    tester,
  ) async {
    late final Harness h;
    h = await devicesScreen(
      tester,
      unlink: (_) {
        h.linkedDevices = [h.linkedDevices.last];
        return problem(404, 'not_found');
      },
    );

    await tapOn(tester, unlinkActions.first);
    await tapOn(
      tester,
      find.descendant(
        of: find.byType(DestructiveConfirmation),
        matching: find.widgetWithText(PrimaryButton, 'Desvincular'),
      ),
    );

    expect(find.text(deviceGone), findsOneWidget);
    expect(find.byType(ErrorNote), findsNothing);
    expect(find.text('Tablet da Lia'), findsNothing);
  });

  testWidgets('with no devices, it says what a linked device is and offers '
      'to link one', (tester) async {
    final h = await devicesScreen(tester, devices: () => []);

    expect(find.text(noDevices), findsOneWidget);
    expect(unlinkActions, findsNothing);
    await tapOn(tester, find.text('Vincular o aparelho da criança'));

    expect(h.location(tester), '/modo-crianca/vincular');
  });

  testWidgets('placeholder rows while loading, then a failed read offers '
      'Tentar de novo', (tester) async {
    final semantics = tester.ensureSemantics();
    final gate = Completer<http.Response>();
    late final Harness h;
    h = await devicesScreen(tester, read: (_) => gate.future);

    expect(find.bySemanticsLabel('Carregando os aparelhos'), findsOneWidget);
    gate.complete(problem(503, 'unavailable'));
    await tester.pumpAndSettle();

    expect(find.text(Copy.genericRetry), findsOneWidget);
    h.parentalRead = null;
    await tapOn(tester, find.text('Tentar de novo'));

    expect(find.text('Tablet da Lia'), findsOneWidget);
    semantics.dispose();
  });
}

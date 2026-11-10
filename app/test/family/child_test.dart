import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/display_title.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/labels.dart';
import 'package:telinha_segura/family/profile_fields.dart';
import 'package:telinha_segura/family/reconsent_screen.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../catalog/fixtures.dart';
import '../screentime/fixtures.dart';
import 'fixtures.dart';

final lia = minorJson('m1', 'Lia');

/// `/familia/criancas/m1/editar` (or [id]'s) over an API that answers each
/// child write with [answer], or by default updates Lia. The child's page
/// it returns to reads her day and her catalogue as usual.
Future<Harness> child(
  WidgetTester tester, {
  Map<String, Object?>? minor,
  String id = 'm1',
  FutureOr<http.Response> Function(http.Request)? answer,
}) async {
  late final Harness h;
  final time = screenTimeApi();
  final videos = catalogApi();
  h = Harness(
    signedIn: true,
    api: (req) {
      final path = req.url.path;
      if (path.startsWith('/v1/screentime/')) return time(req);
      if (!RegExp(r'^/v1/family/minors/[^/]+$').hasMatch(path)) {
        return videos(req);
      }
      if (answer != null) return answer(req);
      final patch = jsonDecode(req.body) as Map<String, dynamic>;
      final updated = {...(minor ?? lia), ...patch};
      h.family = familyWith([updated]);
      return json(200, updated);
    },
  )..family = familyWith([minor ?? lia]);
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: '/familia/criancas/$id/editar');
  return h;
}

/// The profile writes [h] sent, without the reads around them.
List<String> writes(Harness h) =>
    h.actions.where((a) => a.startsWith('PATCH')).toList();

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

VoidCallback? saveOf(WidgetTester tester) => tester
    .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Salvar'))
    .onPressed;

Map<String, dynamic> bodyOf(String call) =>
    jsonDecode(call.substring(call.indexOf('{'))) as Map<String, dynamic>;

void main() {
  group('consent', () {
    testWidgets('a child of "2 a 4 anos" shows the advice about children '
        'under 2 under the bands', (tester) async {
      await child(tester, minor: minorJson('m1', 'Lia', ageBand: 'ate-4'));

      expect(find.text(underTwoAdvice), findsOneWidget);
    });

    testWidgets('a paused child says it needs a new authorization, a door '
        'to it', (tester) async {
      final h = await child(tester, minor: pausedMinorJson('m1', 'Lia'));

      expect(find.widgetWithText(DoorRow, needsConsent), findsOneWidget);
      await tapOn(tester, find.widgetWithText(DoorRow, needsConsent));

      expect(h.location(tester), '/familia/criancas/m1/autorizar');
    });

    testWidgets('a current child says nothing of it', (tester) async {
      await child(tester);

      expect(find.text(needsConsent), findsNothing);
    });
  });

  group('editing', () {
    testWidgets('prefills the three fields; Salvar waits for a change', (
      tester,
    ) async {
      await child(tester);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Lia',
      );
      expect(
        tester.widget<AvatarPicker>(find.byType(AvatarPicker)).value,
        Avatar.fox,
      );
      expect(
        tester.widget<AgeBandChoice>(find.byType(AgeBandChoice)).value,
        AgeBand.from5To8,
      );
      expect(saveOf(tester), isNull);
    });

    testWidgets('a change enables Salvar; undoing it disables it again', (
      tester,
    ) async {
      await child(tester);

      await tapOn(tester, find.byKey(const ValueKey(Avatar.cat)));
      expect(saveOf(tester), isNotNull);

      await tapOn(tester, find.byKey(const ValueKey(Avatar.fox)));
      expect(saveOf(tester), isNull);

      await tester.enterText(find.byType(TextField), ' Lia  ');
      await tester.pumpAndSettle();
      expect(saveOf(tester), isNull, reason: 'the same after trimming');
    });

    testWidgets('Salvar sends only the changed fields, then returns to the '
        'child\'s page', (tester) async {
      final h = await child(tester);

      await tapOn(tester, find.byKey(const ValueKey(Avatar.cat)));
      await tapOn(tester, find.text('Salvar'));

      expect(writes(h), hasLength(1));
      expect(writes(h).single, startsWith('PATCH /v1/family/minors/m1 '));
      expect(bodyOf(writes(h).single), {'avatar': 'cat'});
      expect(h.location(tester), '/familia/criancas/m1');
    });

    testWidgets('a new nickname goes trimmed, alone', (tester) async {
      final h = await child(tester);

      await tester.enterText(find.byType(TextField), '  Lua ');
      await tester.pumpAndSettle();
      await tapOn(tester, find.text('Salvar'));

      expect(bodyOf(writes(h).single), {'nickname': 'Lua'});
      expect(find.widgetWithText(DisplayTitle, 'Lua'), findsOneWidget);
    });

    testWidgets('a nickname that does not fit keeps Salvar disabled', (
      tester,
    ) async {
      await child(tester);

      await tapOn(tester, find.byKey(const ValueKey(Avatar.cat)));
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();

      expect(saveOf(tester), isNull);
    });

    testWidgets('an unknown avatar and age band show the neutral avatar and '
        '"Faixa não informada", chose nothing, and are never sent', (
      tester,
    ) async {
      final h = await child(
        tester,
        minor: minorJson('m1', 'Lia', avatar: 'dragon', ageBand: '13-16'),
      );

      final discs = tester.widgetList<AvatarDisc>(find.byType(AvatarDisc));
      expect(discs.map((d) => d.avatar), contains(Avatar.unknown));
      expect(find.text(AgeBand.unknown.label), findsOneWidget);
      expect(
        tester.widget<AvatarPicker>(find.byType(AvatarPicker)).value,
        isNull,
      );
      expect(
        tester.widget<AgeBandChoice>(find.byType(AgeBandChoice)).value,
        isNull,
      );
      expect(saveOf(tester), isNull);

      await tester.enterText(find.byType(TextField), 'Lua');
      await tester.pumpAndSettle();
      await tapOn(tester, find.text('Salvar'));

      expect(bodyOf(writes(h).single), {'nickname': 'Lua'});
    });

    testWidgets('back returns to the child\'s page', (tester) async {
      final h = await child(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/criancas/m1');
    });

    testWidgets('a dropped connection keeps the changes', (tester) async {
      final h = await child(
        tester,
        answer: (_) => throw http.ClientException('down'),
      );

      await tester.enterText(find.byType(TextField), 'Lua');
      await tester.pumpAndSettle();
      await tapOn(tester, find.text('Salvar'));

      expect(find.text(Copy.genericRetry), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Lua',
      );
      expect(h.location(tester), '/familia/criancas/m1/editar');
    });

    testWidgets('deleting the profile is the child\'s page\'s, not the '
        'form\'s', (tester) async {
      await child(tester);

      expect(find.text('Excluir perfil'), findsNothing);
    });
  });

  group('a profile that no longer exists', () {
    testWidgets('not_found on save says so and returns to the refreshed '
        'list', (tester) async {
      late Harness h;
      h = await child(
        tester,
        answer: (_) {
          h.family = familyWith([]);
          return problem(404, 'not_found');
        },
      );

      await tester.enterText(find.byType(TextField), 'Lua');
      await tester.pumpAndSettle();
      await tapOn(tester, find.text('Salvar'));

      expect(h.location(tester), '/familia/criancas');
      expect(find.text(Copy.childGone), findsOneWidget);
      expect(find.byType(DoorRow), findsNothing);
    });

    testWidgets('an id the family does not hold says so on the list', (
      tester,
    ) async {
      final h = await child(tester, id: 'gone');

      expect(h.location(tester), '/familia/criancas');
      expect(find.text(Copy.childGone), findsOneWidget);
      expect(find.widgetWithText(DoorRow, 'Lia'), findsOneWidget);
    });
  });
}

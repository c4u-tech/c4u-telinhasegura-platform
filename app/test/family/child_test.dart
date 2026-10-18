import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/reauth_prompt.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/family/avatars.dart';
import 'package:telinha_segura/family/confirm.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/labels.dart';
import 'package:telinha_segura/family/profile_fields.dart';
import 'package:telinha_segura/family/reconsent_screen.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import 'fixtures.dart';

final lia = minorJson('m1', 'Lia');

/// `/familia/criancas/m1` (or [id]) over an API that answers each child
/// write with [answer], or by default updates or deletes Lia.
Future<Harness> child(
  WidgetTester tester, {
  Map<String, Object?>? minor,
  String id = 'm1',
  FutureOr<http.Response> Function(http.Request)? answer,
  bool reauth = false,
}) async {
  late final Harness h;
  var confirmed = !reauth;
  h = Harness(
    signedIn: true,
    api: (req) {
      if (req.url.path == '/v1/session/reauth') {
        confirmed = true;
        return http.Response('', 204);
      }
      if (!req.url.path.startsWith('/v1/family/minors/')) {
        return http.Response('', 204);
      }
      if (answer != null) return answer(req);
      if (req.method == 'DELETE') {
        if (!confirmed) return problem(403, 'reauth_required');
        h.family = familyWith([]);
        return http.Response('', 204);
      }
      final patch = jsonDecode(req.body) as Map<String, dynamic>;
      final updated = {...(minor ?? lia), ...patch};
      h.family = familyWith([updated]);
      return json(200, updated);
    },
  )..family = familyWith([minor ?? lia]);
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: '/familia/criancas/$id');
  return h;
}

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

    testWidgets('Salvar sends only the changed fields, then lists the '
        'children', (tester) async {
      final h = await child(tester);

      await tapOn(tester, find.byKey(const ValueKey(Avatar.cat)));
      await tapOn(tester, find.text('Salvar'));

      expect(h.actions, hasLength(1));
      expect(h.actions.single, startsWith('PATCH /v1/family/minors/m1 '));
      expect(bodyOf(h.actions.single), {'avatar': 'cat'});
      expect(h.location(tester), '/familia/criancas');
    });

    testWidgets('a new nickname goes trimmed, alone', (tester) async {
      final h = await child(tester);

      await tester.enterText(find.byType(TextField), '  Lua ');
      await tester.pumpAndSettle();
      await tapOn(tester, find.text('Salvar'));

      expect(bodyOf(h.actions.single), {'nickname': 'Lua'});
      expect(find.widgetWithText(DoorRow, 'Lua'), findsOneWidget);
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

      expect(bodyOf(h.actions.single), {'nickname': 'Lua'});
    });

    testWidgets('back returns to the children', (tester) async {
      final h = await child(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/criancas');
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
      expect(h.location(tester), '/familia/criancas/m1');
    });
  });

  group('Excluir perfil', () {
    testWidgets('asks first, naming the child and saying the profile is '
        'erased and the consent withdrawn', (tester) async {
      final h = await child(tester);
      double edgeOf(Finder finder) => tester.getTopLeft(finder).dx;
      final edge = edgeOf(find.byType(FilledButton));
      expect(edgeOf(find.text('Excluir perfil')), edge);

      await tapOn(tester, find.text('Excluir perfil'));

      final confirmation = tester.widget<DestructiveConfirmation>(
        find.byType(DestructiveConfirmation),
      );
      // A short title; the body's first line names the child.
      expect(confirmation.title, 'Excluir perfil');
      expect(
        confirmation.body.first,
        startsWith('O perfil de Lia será apagado'),
      );
      // One alignment rule: Cancelar starts on the column edge too.
      expect(edgeOf(find.text('Cancelar')), edge);
      final words = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(DestructiveConfirmation),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .join(' ');
      expect(words, contains('Lia'));
      expect(words, contains('apagado'));
      expect(words, contains('consentimento'));
      expect(words, contains('retirado'));
      expect(h.actions, isEmpty);
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      final h = await child(tester);

      await tapOn(tester, find.text('Excluir perfil'));
      await tapOn(tester, find.text('Cancelar'));

      expect(find.byType(DestructiveConfirmation), findsNothing);
      expect(h.actions, isEmpty);
      expect(h.location(tester), '/familia/criancas/m1');
    });

    testWidgets('confirming deletes the child and returns to the refreshed '
        'list', (tester) async {
      final h = await child(tester);

      await tapOn(tester, find.text('Excluir perfil'));
      await tapOn(
        tester,
        find.descendant(
          of: find.byType(DestructiveConfirmation),
          matching: find.widgetWithText(PrimaryButton, 'Excluir perfil'),
        ),
      );

      expect(h.actions, ['DELETE /v1/family/minors/m1']);
      expect(h.location(tester), '/familia/criancas');
      expect(find.widgetWithText(DoorRow, 'Lia'), findsNothing);
      expect(find.text('0 de 10 crianças'), findsOneWidget);
    });

    testWidgets('a stale sign-in asks to confirm it is you, then deletes', (
      tester,
    ) async {
      final h = await child(tester, reauth: true);

      await tapOn(tester, find.text('Excluir perfil'));
      await tapOn(
        tester,
        find.descendant(
          of: find.byType(DestructiveConfirmation),
          matching: find.widgetWithText(PrimaryButton, 'Excluir perfil'),
        ),
      );
      expect(find.byType(ReauthPrompt), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'uma senha longa');
      await tester.pumpAndSettle();
      await tapOn(tester, find.text('Confirmar'));

      expect(h.actions, [
        'DELETE /v1/family/minors/m1',
        'POST /v1/session/reauth {"password":"uma senha longa"}',
        'DELETE /v1/family/minors/m1',
      ]);
      expect(h.location(tester), '/familia/criancas');
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

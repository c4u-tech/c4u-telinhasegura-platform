import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/family/consent.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/labels.dart';
import 'package:telinha_segura/family/new_child_screen.dart';
import 'package:telinha_segura/family/profile_fields.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import 'fixtures.dart';

final nina = minorJson('m9', 'Nina', avatar: 'owl', ageBand: '9-12');

/// `/familia/criancas/nova` over an API whose create answers [create];
/// by default it registers Nina, and the family read then holds her.
Future<Harness> newChild(
  WidgetTester tester, {
  FutureOr<http.Response> Function()? create,
}) async {
  late final Harness h;
  h = Harness(
    signedIn: true,
    api: (req) {
      if (req.method == 'POST' && req.url.path == '/v1/family/minors') {
        if (create != null) return create();
        h.family = familyWith([...ownerFamily['minors']! as List, nina]);
        return json(201, nina);
      }
      return http.Response('', 204);
    },
  )..family = ownerFamily;
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: '/familia/criancas/nova');
  return h;
}

Future<void> fillProfile(
  WidgetTester tester, {
  String nickname = '  Nina ',
  Avatar? avatar = Avatar.owl,
  AgeBand? band = AgeBand.from9To12,
}) async {
  await tester.enterText(find.byType(TextField), nickname);
  await tester.pumpAndSettle();
  if (avatar != null) await tapOn(tester, find.byKey(ValueKey(avatar)));
  if (band != null) await tapOn(tester, find.text(band.label));
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

VoidCallback? pressOf(WidgetTester tester, String label) => tester
    .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, label))
    .onPressed;

Future<void> toConsent(WidgetTester tester) async {
  await fillProfile(tester);
  await tapOn(tester, find.text('Continuar'));
}

void main() {
  group('step 1', () {
    testWidgets('choosing "2 a 4 anos" shows the advice about children '
        'under 2, and Continuar still goes on', (tester) async {
      await newChild(tester);
      expect(find.text(underTwoAdvice), findsNothing);

      await fillProfile(tester, band: AgeBand.upTo4);

      expect(find.text(underTwoAdvice), findsOneWidget);
      expect(pressOf(tester, 'Continuar'), isNotNull);
    });

    testWidgets('asks for the nickname, the avatar and the age band, none '
        'chosen, Continuar waiting', (tester) async {
      await newChild(tester);

      final marks = tester.widget<StepMarks>(find.byType(StepMarks));
      expect((marks.step, marks.of), (1, 2));
      expect(find.text('Apelido'), findsOneWidget);
      expect(find.byType(AvatarPicker), findsOneWidget);
      expect(
        tester.widget<AvatarPicker>(find.byType(AvatarPicker)).value,
        isNull,
      );
      expect(
        tester.widget<AgeBandChoice>(find.byType(AgeBandChoice)).value,
        isNull,
      );
      expect(pressOf(tester, 'Continuar'), isNull);
      expect(find.text(profileHint), findsOneWidget);
    });

    for (final (what, nickname, avatar, band) in [
      ('a blank nickname', '   ', Avatar.owl, AgeBand.upTo4),
      ('a nickname past 20', 'a' * 21, Avatar.owl, AgeBand.upTo4),
      ('no avatar', 'Nina', null, AgeBand.upTo4),
      ('no age band', 'Nina', Avatar.owl, null),
    ]) {
      testWidgets('Continuar stays disabled with $what', (tester) async {
        await newChild(tester);

        await fillProfile(
          tester,
          nickname: nickname,
          avatar: avatar,
          band: band,
        );

        expect(pressOf(tester, 'Continuar'), isNull);
      });
    }

    testWidgets('all three valid enable Continuar', (tester) async {
      await newChild(tester);

      await fillProfile(tester);

      expect(pressOf(tester, 'Continuar'), isNotNull);
      expect(find.text(profileHint), findsNothing);
    });

    testWidgets('back returns to the children', (tester) async {
      final h = await newChild(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/criancas');
    });
  });

  group('step 2', () {
    testWidgets('shows the consent text and an unchecked declaration; '
        'Cadastrar waits for it', (tester) async {
      await newChild(tester);
      await toConsent(tester);

      final marks = tester.widget<StepMarks>(find.byType(StepMarks));
      expect((marks.step, marks.of), (2, 2));
      // A short screen title; the Appendix heading opens the text itself.
      expect(
        tester.widget<FieldLayout>(find.byType(FieldLayout)).title,
        'Consentimento',
      );
      expect(find.text(ConsentText.title), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(ConsentText.title)).dy,
        lessThan(tester.getTopLeft(find.text(ConsentText.paragraphs.first)).dy),
      );
      for (final paragraph in ConsentText.paragraphs) {
        expect(find.text(paragraph), findsOneWidget);
      }
      final declaration = find.widgetWithText(
        DeclarationRow,
        ConsentText.declaration,
      );
      expect(tester.widget<DeclarationRow>(declaration).value, isFalse);
      expect(pressOf(tester, 'Cadastrar'), isNull);
      expect(find.text(declarationHint), findsOneWidget);

      await tapOn(tester, declaration);

      expect(tester.widget<DeclarationRow>(declaration).value, isTrue);
      expect(pressOf(tester, 'Cadastrar'), isNotNull);
    });

    testWidgets('the privacy policy the text names opens outside the app', (
      tester,
    ) async {
      final h = await newChild(tester);
      await toConsent(tester);

      await tapOn(tester, find.text(ConsentText.privacyLabel));

      expect(h.links.opened, [ConsentText.privacyUrl]);
    });

    testWidgets('names the child it is about', (tester) async {
      await newChild(tester);
      await toConsent(tester);

      expect(find.text('Nina'), findsOneWidget);
      expect(find.text(AgeBand.from9To12.label), findsOneWidget);
    });

    testWidgets('going back keeps the step 1 values', (tester) async {
      await newChild(tester);
      await toConsent(tester);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(find.byType(AvatarPicker), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '  Nina ',
      );
      expect(
        tester.widget<AvatarPicker>(find.byType(AvatarPicker)).value,
        Avatar.owl,
      );
      expect(
        tester.widget<AgeBandChoice>(find.byType(AgeBandChoice)).value,
        AgeBand.from9To12,
      );
      expect(pressOf(tester, 'Continuar'), isNotNull);
    });
  });

  group('Cadastrar', () {
    testWidgets('creates the child with the consent version shown, then '
        'lists the new child', (tester) async {
      final h = await newChild(tester);
      await toConsent(tester);

      await tapOn(tester, find.text(ConsentText.declaration));
      await tapOn(tester, find.text('Cadastrar'));

      expect(h.actions, hasLength(1));
      final call = h.actions.single;
      expect(call, startsWith('POST /v1/family/minors '));
      expect(jsonDecode(call.substring(call.indexOf('{'))), {
        'nickname': 'Nina',
        'avatar': 'owl',
        'age_band': '9-12',
        'consent': {'policy_version': ConsentText.version},
      });
      expect(h.location(tester), '/familia/criancas');
      expect(find.widgetWithText(DoorRow, 'Nina'), findsOneWidget);
    });

    testWidgets('policy_outdated asks to update the app and keeps the values', (
      tester,
    ) async {
      await newChild(tester, create: () => problem(409, 'policy_outdated'));
      await toConsent(tester);

      await tapOn(tester, find.text(ConsentText.declaration));
      await tapOn(tester, find.text('Cadastrar'));

      expect(
        find.text(
          Copy.forError(const ApiError(status: 409, code: 'policy_outdated')),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('atualize o app'), findsOneWidget);
      expect(
        tester.widget<DeclarationRow>(find.byType(DeclarationRow)).value,
        isTrue,
      );
      await tapOn(tester, find.byTooltip('Voltar'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '  Nina ',
      );
    });

    testWidgets('limit_reached says the family is full', (tester) async {
      await newChild(tester, create: () => problem(409, 'limit_reached'));
      await toConsent(tester);

      await tapOn(tester, find.text(ConsentText.declaration));
      await tapOn(tester, find.text('Cadastrar'));

      expect(find.text(Copy.childrenFull), findsOneWidget);
    });

    testWidgets('disables Cadastrar while pending; a dropped connection '
        'keeps everything', (tester) async {
      final answer = Completer<http.Response>();
      final h = await newChild(tester, create: () => answer.future);
      await toConsent(tester);
      await tapOn(tester, find.text(ConsentText.declaration));

      await tester.ensureVisible(find.text('Cadastrar'));
      await tester.tap(find.text('Cadastrar'));
      await tester.pump();
      final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(button.busy, isTrue);

      answer.completeError(http.ClientException('down'));
      await tester.pumpAndSettle();

      expect(h.actions, hasLength(1));
      expect(find.text(Copy.genericRetry), findsOneWidget);
      expect(pressOf(tester, 'Cadastrar'), isNotNull);
      expect(h.location(tester), '/familia/criancas/nova');
    });
  });
}

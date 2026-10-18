import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/family/consent.dart';
import 'package:telinha_segura/family/family.dart';
import 'package:telinha_segura/family/labels.dart';
import 'package:telinha_segura/family/reconsent_screen.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import 'fixtures.dart';
import 'new_child_test.dart' show pressOf, tapOn;

/// `/familia/criancas/m1/autorizar` (or [initial]) for a family holding
/// Lia, paused; the consent answers [grant], by default 204 with Lia then
/// current.
Future<Harness> reconsent(
  WidgetTester tester, {
  String initial = '/familia/criancas/m1/autorizar',
  FutureOr<http.Response> Function()? grant,
}) async {
  late final Harness h;
  h = Harness(
    signedIn: true,
    api: (req) {
      if (req.method == 'POST' &&
          req.url.path == '/v1/family/minors/m1/consent') {
        if (grant != null) return grant();
        h.family = familyWith([minorJson('m1', 'Lia', consentCurrent: true)]);
        return http.Response('', 204);
      }
      return http.Response('', 204);
    },
  )..family = familyWith([pausedMinorJson('m1', 'Lia')]);
  unawaited(h.services.familyModel.load());
  await h.pump(tester, initial: initial);
  return h;
}

Future<void> authorize(WidgetTester tester) async {
  await tapOn(tester, find.text(ConsentText.reconsentDeclaration));
  await tapOn(tester, find.text('Autorizar'));
}

void main() {
  testWidgets('names the child, shows the whole text under its own title '
      'and an unchecked declaration; Autorizar waits for it', (tester) async {
    await reconsent(tester);

    expect(find.byType(ReconsentScreen), findsOneWidget);
    expect(find.text('Lia'), findsOneWidget);
    expect(find.text(AgeBand.from5To8.label), findsOneWidget);
    expect(find.text(ConsentText.reconsentTitle), findsOneWidget);
    expect(find.text(ConsentText.title), findsNothing);
    for (final paragraph in ConsentText.paragraphs) {
      expect(find.text(paragraph), findsOneWidget);
    }
    final declaration = find.widgetWithText(
      DeclarationRow,
      ConsentText.reconsentDeclaration,
    );
    expect(tester.widget<DeclarationRow>(declaration).value, isFalse);
    expect(pressOf(tester, 'Autorizar'), isNull);
    expect(find.text(declarationHint), findsOneWidget);

    await tapOn(tester, declaration);

    expect(pressOf(tester, 'Autorizar'), isNotNull);
  });

  testWidgets('the privacy policy opens outside the app', (tester) async {
    final h = await reconsent(tester);

    await tapOn(tester, find.text(ConsentText.privacyLabel));

    expect(h.links.opened, [ConsentText.privacyUrl]);
  });

  testWidgets('Autorizar records the consent to the text shown, reads the '
      'family again and lists the child as current', (tester) async {
    final h = await reconsent(tester);
    final reads = h.calls.where((c) => c == 'GET /v1/family').length;

    await authorize(tester);

    final call = h.actions.single;
    expect(call, startsWith('POST /v1/family/minors/m1/consent '));
    expect(jsonDecode(call.substring(call.indexOf('{'))), {
      'policy_version': kConsentPolicyVersion,
    });
    expect(
      h.calls.where((c) => c == 'GET /v1/family').length,
      greaterThan(reads),
    );
    expect(h.location(tester), '/familia/criancas');
    expect(find.widgetWithText(DoorRow, 'Lia'), findsOneWidget);
    expect(find.text(needsConsent), findsNothing);
  });

  testWidgets('opened from the hand-over, it returns there', (tester) async {
    final h = await reconsent(
      tester,
      initial: '/familia/criancas/m1/autorizar?depois=/modo-crianca/entregar',
    );

    await authorize(tester);

    expect(h.location(tester), '/modo-crianca/entregar');
  });

  testWidgets('a return anywhere else is dropped for the children', (
    tester,
  ) async {
    final h = await reconsent(
      tester,
      initial: '/familia/criancas/m1/autorizar?depois=https://example.com',
    );

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/criancas');
  });

  testWidgets('policy_outdated asks to update the app and keeps the '
      'declaration', (tester) async {
    await reconsent(tester, grant: () => problem(409, 'policy_outdated'));

    await authorize(tester);

    expect(
      find.text(
        Copy.forError(const ApiError(status: 409, code: 'policy_outdated')),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<DeclarationRow>(find.byType(DeclarationRow)).value,
      isTrue,
    );
  });

  testWidgets('not_found goes back to the children, saying the profile is '
      'gone', (tester) async {
    late Harness h;
    h = await reconsent(
      tester,
      grant: () {
        h.family = familyWith([]);
        return problem(404, 'not_found');
      },
    );

    await authorize(tester);

    expect(h.location(tester), '/familia/criancas');
    expect(find.text(Copy.childGone), findsOneWidget);
  });

  testWidgets('opened for a child the family does not hold, it goes back '
      'to the children', (tester) async {
    final h = await reconsent(
      tester,
      initial: '/familia/criancas/m9/autorizar',
    );
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/criancas');
    expect(find.text(Copy.childGone), findsOneWidget);
  });
}

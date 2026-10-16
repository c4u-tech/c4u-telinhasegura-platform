import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/pack_decision_screens.dart';
import 'package:telinha_segura/curation/pack_parts.dart';
import 'package:telinha_segura/curation/pack_review_screen.dart';
import 'package:telinha_segura/family/widgets.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';
import 'appoint_screen_test.dart' show tapOn;

Future<Harness> reviewPack(
  WidgetTester tester, {
  Map<String, Object?>? pack,
  FutureOr<http.Response> Function(String id)? read,
  FutureOr<http.Response> Function(http.Request)? write,
  String initial = '/pacotinhos/p1',
}) async {
  final h =
      Harness(
          signedIn: true,
          api: packApi(
            pack: read ?? (_) => json(200, pack ?? reviewable),
            write:
                write ?? (_) => json(201, {'review': null, 'state': 'pending'}),
          ),
        )
        ..family = ownerFamily
        ..roles = ['curator'];
  await h.pump(tester, initial: initial);
  return h;
}

final reviewable = packOf(
  'p1',
  'Hora do banho',
  round: 2,
  reviewable: true,
  composer: 'pedagogo',
  reviews: [
    {
      'display_role': 'mae-pai',
      'decision': 'approve',
      'reason': null,
      'reviewed_at': '2026-10-06T12:00:00Z',
    },
  ],
);

List<String> writes(Harness h) =>
    h.actions.where((a) => !a.startsWith('GET')).toList();

void main() {
  group('the review', () {
    testWidgets('reads the round, then the videos in order, then the '
        'decision doors', (tester) async {
      await reviewPack(tester);

      expect(find.text('Revisar pacotinho'), findsOneWidget);
      expect(find.text('Hora do banho'), findsOneWidget);
      expect(find.text(nb('Montado por Pedagogo(a) · Rodada 2')), findsOne);
      expect(find.text('Mãe ou pai aprovou'), findsOneWidget);
      expect(find.text('1. Galinha Pintadinha'), findsOneWidget);
      expect(find.text('3. Pato Pateta'), findsOneWidget);
      expect(find.text('Total: 12 min'), findsOneWidget);
      final round = tester.getTopLeft(find.text('Mãe ou pai aprovou')).dy;
      final videos = tester.getTopLeft(find.text('1. Galinha Pintadinha')).dy;
      final approve = tester.getTopLeft(find.text('Aprovar')).dy;
      expect(round, lessThan(videos));
      expect(videos, lessThan(approve));
      expect(find.widgetWithText(DoorRow, 'Recusar'), findsOneWidget);
      expect(
        find.widgetWithText(QuietAction, 'Mudar o pacotinho'),
        findsOneWidget,
      );
    });

    testWidgets('a round nobody reviewed says so; a refusal shows its '
        'reason', (tester) async {
      await reviewPack(
        tester,
        pack: packOf(
          'p1',
          'Hora do banho',
          state: 'held',
          reviews: [
            {
              'display_role': 'psicologo',
              'decision': 'reject',
              'reason': 'Longo demais para a hora de dormir.',
              'reviewed_at': '2026-10-06T12:00:00Z',
            },
          ],
        ),
      );
      expect(find.text('Psicólogo(a) recusou'), findsOneWidget);
      expect(find.text('Longo demais para a hora de dormir.'), findsOneWidget);
      expect(find.text(heldVersion), findsOneWidget);
    });

    testWidgets('with no review yet it says so', (tester) async {
      await reviewPack(tester, pack: packOf('p1', 'Hora do banho'));

      expect(find.text(noPackReviews), findsOneWidget);
    });

    testWidgets('a published pacotinho under review says children keep the '
        'published version', (tester) async {
      await reviewPack(
        tester,
        pack: packOf(
          'p1',
          'Hora do banho',
          state: 'approved',
          reviewable: true,
        ),
      );

      expect(find.text(publishedKeeps), findsOneWidget);
    });

    testWidgets('a round the curator cannot review offers no decision, and '
        'says others review it', (tester) async {
      await reviewPack(tester, pack: packOf('p1', 'Hora do banho'));

      expect(find.widgetWithText(DoorRow, 'Aprovar'), findsNothing);
      expect(find.widgetWithText(DoorRow, 'Recusar'), findsNothing);
      expect(find.text(othersReview), findsOneWidget);
    });

    testWidgets('a video out of the catalogue is marked', (tester) async {
      await reviewPack(
        tester,
        pack: packOf(
          'p1',
          'Hora do banho',
          videos: [
            packVideoJson('v1', 'Galinha Pintadinha'),
            packVideoJson('v2', 'Sapo Cururu', state: 'held'),
            packVideoJson('v3', 'Pato Pateta'),
          ],
        ),
      );

      expect(
        find.text(nb('Canal Bichos · 4 min · $outOfCatalogue')),
        findsOneWidget,
      );
    });

    testWidgets('"Mudar o pacotinho" opens the composer for this one', (
      tester,
    ) async {
      final h = await reviewPack(tester);

      await tapOn(tester, find.text('Mudar o pacotinho'));
      expect(h.location(tester), '/pacotinhos/p1/mudar');
    });

    testWidgets('not_found on the read goes back to the list with a notice', (
      tester,
    ) async {
      final h = await reviewPack(
        tester,
        read: (_) => problem(404, 'not_found'),
      );

      expect(h.location(tester), '/pacotinhos');
      expect(
        find.widgetWithText(Notice, 'Esse pacotinho foi removido.'),
        findsOneWidget,
      );
    });
  });

  group('watching one video', () {
    testWidgets('a video row opens its own screen, the video loaded in the '
        'adult player', (tester) async {
      final h = await reviewPack(tester);

      await tapOn(tester, find.text('2. Sapo Cururu'));

      expect(h.location(tester), '/pacotinhos/p1/videos/v2');
      expect(find.text('Sapo Cururu'), findsOneWidget);
      expect(h.adultPlayer.current!.youtubeId, 'yt-v2');
      await tapOn(tester, find.byTooltip('Voltar'));
      expect(h.location(tester), '/pacotinhos/p1');
    });
  });

  group('approving', () {
    testWidgets('says what approving confirms, approves once, then the '
        'done state', (tester) async {
      final h = await reviewPack(tester);

      await tapOn(tester, find.text('Aprovar'));
      expect(h.location(tester), '/pacotinhos/p1/aprovar');
      expect(find.text(approvePackLead), findsOneWidget);
      await tapOn(tester, find.widgetWithText(PrimaryButton, 'Aprovar'));

      expect(writes(h), [
        'POST /v1/curation/packs/p1/reviews {"decision":"approve"}',
      ]);
      expect(find.widgetWithText(Notice, packApproved), findsOneWidget);
      await tapOn(tester, find.text('Voltar para pacotinhos'));
      expect(h.location(tester), '/pacotinhos');
    });

    for (final (code, status, notice) in [
      (
        'own_composition',
        403,
        'Você montou essa versão, então a revisão dela fica com outros '
            'curadores.',
      ),
      ('already_reviewed', 409, 'Você já revisou essa versão.'),
      ('not_reviewable', 409, 'Essa versão não está mais esperando revisão.'),
      ('not_found', 404, 'Esse pacotinho foi removido.'),
    ]) {
      testWidgets('$code goes back to the list with its notice', (
        tester,
      ) async {
        final h = await reviewPack(
          tester,
          initial: '/pacotinhos/p1/aprovar',
          write: (_) => problem(status, code),
        );

        await tapOn(tester, find.widgetWithText(PrimaryButton, 'Aprovar'));

        expect(h.location(tester), '/pacotinhos');
        expect(find.widgetWithText(Notice, notice), findsOneWidget);
      });
    }
  });

  group('refusing', () {
    testWidgets('waits for a reason, refuses once with it, then the done '
        'state', (tester) async {
      final h = await reviewPack(tester, initial: '/pacotinhos/p1/recusar');

      expect(find.text('Hora do banho'), findsOneWidget);
      expect(find.text(refusePackLead), findsOneWidget);
      final refuse = find.widgetWithText(PrimaryButton, 'Recusar');
      expect(tester.widget<PrimaryButton>(refuse).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '  Longo demais.  ');
      await tester.pumpAndSettle();
      await tapOn(tester, refuse);

      expect(writes(h), [
        'POST /v1/curation/packs/p1/reviews '
            '{"decision":"reject","reason":"Longo demais."}',
      ]);
      expect(find.widgetWithText(Notice, packRefused), findsOneWidget);
    });

    testWidgets('validation lands on the field', (tester) async {
      await reviewPack(
        tester,
        initial: '/pacotinhos/p1/recusar',
        write: (_) => problem(422, 'validation'),
      );

      await tester.enterText(find.byType(TextField), 'x');
      await tester.pumpAndSettle();
      await tapOn(tester, find.widgetWithText(PrimaryButton, 'Recusar'));

      expect(find.text(packReasonInvalid), findsOneWidget);
    });
  });
}

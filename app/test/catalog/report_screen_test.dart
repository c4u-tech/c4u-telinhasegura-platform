import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/catalog/words.dart';
import 'package:telinha_segura/family/profile_fields.dart';

import '../access/harness.dart';
import '../curation/fixtures.dart' show nb;
import '../curation/appoint_screen_test.dart' show tapOn;
import 'child_catalog_screen_test.dart' show row;
import 'family_video_screen_test.dart' show video;
import 'fixtures.dart';

/// The report opened from the video's screen in Lia's catalogue.
Future<Harness> reporting(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? write,
}) async {
  final h = await video(tester, write: write);
  await tapOn(tester, find.text('Denunciar este vídeo'));
  return h;
}

Finder reason(String label) => find.widgetWithText(SelectableRow, label);
Finder get send => find.widgetWithText(FilledButton, 'Denunciar');
Finder get note => find.widgetWithText(TextField, 'Nota (opcional)');

List<String> sent(Harness h) =>
    h.actions.where((a) => a.startsWith('POST /v1/reports')).toList();

const reasons = [
  'Conteúdo inadequado',
  'Assustador',
  'Publicidade',
  'Outro motivo',
];

void main() {
  testWidgets('reads in order: the heading, what a report does, the four '
      'reasons, the note, then the ink primary', (tester) async {
    await reporting(tester);

    expect(find.text('Denunciar'), findsWidgets);
    final order = [
      find.text('O sapo que pulava alto'),
      find.text(nb('Ciência Pequena · 6 min')),
      find.text(reportLead),
      find.text('Motivo'),
      for (final r in reasons) reason(r),
      note,
      send,
    ];
    for (final f in order) {
      expect(f, findsOneWidget);
    }
    final tops = [for (final f in order) tester.getTopLeft(f).dy];
    expect(tops, [...tops]..sort());
    for (final r in reasons) {
      expect(tester.widget<SelectableRow>(reason(r)).selected, isFalse);
    }
  });

  testWidgets('the primary is the ordinary ink primary, never clay', (
    tester,
  ) async {
    await reporting(tester);

    expect(find.widgetWithText(PrimaryButton, 'Denunciar'), findsOneWidget);
  });

  testWidgets('with no reason, the primary waits with its hint', (
    tester,
  ) async {
    await reporting(tester);

    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    expect(find.text(reportHint), findsOneWidget);

    await tapOn(tester, reason('Publicidade'));
    expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
  });

  testWidgets('a reason is a radio, chosen alone', (tester) async {
    final semantics = tester.ensureSemantics();
    await reporting(tester);

    await tapOn(tester, reason('Assustador'));
    await tapOn(tester, reason('Outro motivo'));

    expect(
      tester.widget<SelectableRow>(reason('Assustador')).selected,
      isFalse,
    );
    expect(
      tester.widget<SelectableRow>(reason('Outro motivo')).selected,
      isTrue,
    );
    expect(
      tester.getSemantics(reason('Outro motivo')),
      isSemantics(
        label: 'Outro motivo',
        isInMutuallyExclusiveGroup: true,
        hasCheckedState: true,
        isChecked: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('it sends the reason and the trimmed note once', (tester) async {
    final h = await reporting(tester);

    await tapOn(tester, reason('Assustador'));
    await tester.enterText(note, '  Tem um monstro no fim.  ');
    await tapOn(tester, send);

    expect(sent(h), hasLength(1));
    final body = jsonDecode(sent(h).single.split(' ').skip(2).join(' '));
    expect(body, {
      'video_id': 'v1',
      'reason': 'assustador',
      'note': 'Tem um monstro no fim.',
    });
  });

  testWidgets('a blank note is sent as none', (tester) async {
    final h = await reporting(tester);

    await tapOn(tester, reason('Publicidade'));
    await tester.enterText(note, '   ');
    await tapOn(tester, send);

    final body = jsonDecode(sent(h).single.split(' ').skip(2).join(' '));
    expect(body, {'video_id': 'v1', 'reason': 'publicidade'});
  });

  testWidgets('the note shows its count near the 500 bound', (tester) async {
    await reporting(tester);

    await tester.enterText(note, 'a' * 399);
    await tester.pump();
    expect(find.text('399 de 500'), findsNothing);
    await tester.enterText(note, 'a' * 450);
    await tester.pump();
    expect(find.text('450 de 500'), findsOneWidget);
    await tester.enterText(note, 'a' * 600);
    await tester.pump();
    expect(find.text('500 de 500'), findsOneWidget);
  });

  testWidgets('a new report ends on its done state; back on the '
      'catalogue, the video is gone', (tester) async {
    final h = await reporting(tester);
    h.api = catalogApi(catalog: (_, _) => page(liaVideos.skip(1).toList()));

    await tapOn(tester, reason('Assustador'));
    await tapOn(tester, send);

    expect(find.widgetWithText(Notice, reportNew), findsOneWidget);
    expect(send, findsNothing);
    expect(reason('Assustador'), findsNothing);
    await tapOn(
      tester,
      find.widgetWithText(FilledButton, CatalogWords.backTo('Lia')),
    );
    expect(h.location(tester), '/familia/videos/m1');
    expect(row('O sapo que pulava alto'), findsNothing);
    expect(row('Gatinhos no quintal'), findsOneWidget);
  });

  testWidgets('a report the family had already made says so', (tester) async {
    await reporting(
      tester,
      write: (req) => req.url.path == '/v1/reports'
          ? http.Response('', 200)
          : http.Response('', 204),
    );

    await tapOn(tester, reason('Assustador'));
    await tapOn(tester, send);

    expect(find.widgetWithText(Notice, reportExisting), findsOneWidget);
  });

  testWidgets('rate_limited shows the countdown and keeps the reason and '
      'the note', (tester) async {
    await reporting(
      tester,
      write: (_) => problem(429, 'rate_limited', retryAfterBody: 3),
    );

    await tapOn(tester, reason('Assustador'));
    await tester.enterText(note, 'Tem um monstro.');
    await tapOn(tester, send);

    expect(
      find.widgetWithText(ErrorNote, Copy.retryIn(const Duration(seconds: 3))),
      findsOneWidget,
    );
    expect(tester.widget<SelectableRow>(reason('Assustador')).selected, isTrue);
    expect(find.text('Tem um monstro.'), findsOneWidget);
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
  });

  testWidgets('a failed send shows the error note and keeps the choice', (
    tester,
  ) async {
    await reporting(tester, write: (_) => problem(503, 'unavailable'));

    await tapOn(tester, reason('Outro motivo'));
    await tapOn(tester, send);

    expect(find.byType(ErrorNote), findsOneWidget);
    expect(
      tester.widget<SelectableRow>(reason('Outro motivo')).selected,
      isTrue,
    );
  });

  testWidgets('a video no longer there goes back to the catalogue with a '
      'notice', (tester) async {
    final h = await reporting(tester, write: (_) => problem(404, 'not_found'));

    await tapOn(tester, reason('Assustador'));
    await tapOn(tester, send);

    expect(h.location(tester), '/familia/videos/m1');
    expect(find.widgetWithText(Notice, videoGone), findsOneWidget);
  });

  testWidgets('back returns to the video, still loaded', (tester) async {
    final h = await reporting(tester);

    await tester.tap(find.byTooltip('Voltar').last);
    await tester.pumpAndSettle();

    expect(h.location(tester), '/familia/videos/m1/v1');
    expect(h.adultPlayer.current!.closed, isFalse);
  });

  testWidgets('opened by its address, it reads the catalogue to name the '
      'video', (tester) async {
    final h = Harness(signedIn: true, api: catalogApi())
      ..family = threeChildren;
    await h.pump(tester, initial: '/familia/videos/m1/v2/denunciar');

    expect(find.text('Gatinhos no quintal'), findsOneWidget);
    expect(find.text(reportLead), findsOneWidget);
  });
}

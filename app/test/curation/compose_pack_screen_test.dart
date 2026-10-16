import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/curation/compose_pack_screen.dart';
import 'package:telinha_segura/family/profile_fields.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';
import 'appoint_screen_test.dart' show tapOn;

/// Approved videos of [theme] as the picker reads them, 4 minutes each
/// unless [seconds] says otherwise.
http.Response approvedOf(
  String theme,
  List<String> titles, {
  int seconds = 240,
  int? next,
}) => queuePage([
  for (final t in titles)
    {
      ...queuedJson(
        '$theme-${t.toLowerCase()}',
        t,
        channel: 'Canal $t',
        seconds: seconds,
      ),
      'state': 'approved',
      'theme': theme,
      'min_age_band': 'ate-4',
    },
], next: next);

Future<Harness> composer(
  WidgetTester tester, {
  FutureOr<http.Response> Function(http.Request)? videos,
  FutureOr<http.Response> Function(String id)? pack,
  FutureOr<http.Response> Function(http.Request)? write,
  FutureOr<http.Response> Function()? limits,
  String initial = '/pacotinhos/novo',
}) async {
  final h =
      Harness(
          signedIn: true,
          api: packApi(
            videos:
                videos ??
                (req) => approvedOf(req.url.queryParameters['theme']!, [
                  'Abelha',
                  'Baleia',
                  'Coelho',
                  'Dromedário',
                  'Elefante',
                  'Foca',
                ]),
            pack: pack,
            write: write,
            limits: limits,
          ),
        )
        ..family = ownerFamily
        ..roles = ['curator'];
  await h.pump(tester, initial: initial);
  return h;
}

Finder get send => find.widgetWithText(PrimaryButton, 'Enviar para revisão');

List<String> writes(Harness h) =>
    h.actions.where((a) => !a.startsWith('GET')).toList();

/// Opens the picker, chooses [theme], picks [titles], and comes back.
Future<void> pick(
  WidgetTester tester,
  List<String> titles, {
  String theme = 'Bichos',
}) async {
  await tapOn(tester, find.text('Adicionar vídeos'));
  await tapOn(tester, find.widgetWithText(SelectableRow, theme));
  for (final t in titles) {
    await tapOn(tester, find.widgetWithText(SelectableRow, t));
  }
  await tapOn(tester, find.widgetWithText(PrimaryButton, 'Pronto'));
}

Future<void> name(WidgetTester tester, String text) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Nome do pacotinho'),
    text,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('composing', () {
    testWidgets('starts empty: the sections in order, the primary waiting '
        'with what is missing', (tester) async {
      await composer(tester);

      expect(find.text('Montar pacotinho'), findsOneWidget);
      final order = [
        'Vídeos',
        'Adicionar vídeos',
        'Nome do pacotinho',
        'Capa',
        'Tema',
      ].map((t) => tester.getTopLeft(find.text(t).first).dy).toList();
      expect(order, orderedEquals([...order]..sort()));
      expect(tester.widget<PrimaryButton>(send).onPressed, isNull);
      expect(find.text(needsVideos(3)), findsOneWidget);
      expect(find.textContaining('min de'), findsNothing, reason: 'no total');
    });

    testWidgets('picks from a theme come back numbered, with the total '
        'against the limit, and preset the theme', (tester) async {
      final h = await composer(tester);

      await pick(tester, ['Baleia', 'Abelha', 'Coelho']);

      expect(h.location(tester), '/pacotinhos/novo');
      expect(h.actions, contains('GET /v1/curation/videos?theme=bichos'));
      expect(find.text('1. Baleia'), findsOneWidget);
      expect(find.text('2. Abelha'), findsOneWidget);
      expect(find.text('3. Coelho'), findsOneWidget);
      expect(find.text(nb('3 de 5 vídeos · 12 min de 20')), findsOneWidget);
      expect(
        tester
            .widget<SelectableRow>(find.widgetWithText(SelectableRow, 'Bichos'))
            .selected,
        isTrue,
      );
    });

    testWidgets('in the picker, the picked rows show selected and at five '
        'the rest wait with the hint', (tester) async {
      await composer(tester);
      await pick(tester, ['Abelha']);

      await tapOn(tester, find.text('Adicionar vídeos'));
      await tapOn(tester, find.widgetWithText(SelectableRow, 'Bichos'));
      expect(
        tester
            .widget<SelectableRow>(find.widgetWithText(SelectableRow, 'Abelha'))
            .selected,
        isTrue,
      );
      for (final t in ['Baleia', 'Coelho', 'Dromedário', 'Elefante']) {
        await tapOn(tester, find.widgetWithText(SelectableRow, t));
      }

      expect(find.text(pickerFull), findsOneWidget);
      expect(
        tester
            .widget<SelectableRow>(find.widgetWithText(SelectableRow, 'Foca'))
            .onTap,
        isNull,
      );
    });

    testWidgets('leaving the picker by back changes nothing', (tester) async {
      final h = await composer(tester);
      await pick(tester, ['Abelha']);

      await tapOn(tester, find.text('Adicionar vídeos'));
      await tapOn(tester, find.widgetWithText(SelectableRow, 'Bichos'));
      await tapOn(tester, find.widgetWithText(SelectableRow, 'Baleia'));
      await tapOn(tester, find.byTooltip('Voltar'));

      expect(h.location(tester), '/pacotinhos/novo');
      expect(find.text('1. Abelha'), findsOneWidget);
      expect(find.textContaining('Baleia'), findsNothing);
    });

    testWidgets('"Descer" and "Subir" reorder, absent at the ends, and the '
        'move is announced', (tester) async {
      await composer(tester);
      await pick(tester, ['Abelha', 'Baleia', 'Coelho']);

      expect(find.byTooltip('Subir Abelha'), findsNothing);
      expect(find.byTooltip('Descer Coelho'), findsNothing);
      await tapOn(tester, find.byTooltip('Descer Abelha'));

      expect(find.text('1. Baleia'), findsOneWidget);
      expect(find.text('2. Abelha'), findsOneWidget);
      await tapOn(tester, find.byTooltip('Subir Coelho'));
      expect(find.text('2. Coelho'), findsOneWidget);
      expect(find.text('3. Abelha'), findsOneWidget);
    });

    testWidgets('"Tirar" takes a video out, and a cover taken out falls back '
        'to the first', (tester) async {
      await composer(tester);
      await pick(tester, ['Abelha', 'Baleia', 'Coelho']);

      expect(coverChosen(tester), 'Abelha');
      // Each cover reads by its words, not by the picture alone, three to
      // a row at the phone's width.
      expect(
        tester.getTopLeft(coverOf('Coelho')).dy,
        tester.getTopLeft(coverOf('Abelha')).dy,
      );
      expect(
        find.descendant(
          of: coverOf('Coelho'),
          matching: find.text('3\u00A0·\u00A0Coelho'),
        ),
        findsOneWidget,
      );
      await tapOn(tester, coverOf('Coelho'));
      expect(coverChosen(tester), 'Coelho');
      await tapOn(tester, find.byTooltip('Tirar Coelho'));

      expect(find.textContaining('Coelho'), findsNothing);
      expect(coverChosen(tester), 'Abelha');
      expect(find.text(needsVideos(3)), findsOneWidget);
    });

    testWidgets('over the duration limit the total says so and the primary '
        'waits', (tester) async {
      await composer(
        tester,
        videos: (req) =>
            approvedOf('bichos', ['Abelha', 'Baleia', 'Coelho'], seconds: 480),
      );
      await pick(tester, ['Abelha', 'Baleia', 'Coelho']);
      await name(tester, 'Hora do banho');

      expect(
        find.text(nb('3 de 5 vídeos · 24 min de 20 · acima do limite')),
        findsOneWidget,
      );
      expect(find.text(overLimit), findsOneWidget);
      expect(tester.widget<PrimaryButton>(send).onPressed, isNull);
    });

    testWidgets('sends the composition once, in order, then the done state', (
      tester,
    ) async {
      final h = await composer(tester);
      await pick(tester, ['Baleia', 'Abelha', 'Coelho']);
      await tapOn(tester, coverOf('Abelha'));
      await name(tester, '  Hora do banho  ');
      expect(find.text(needsName), findsNothing);

      await tapOn(tester, send);

      expect(writes(h), hasLength(1));
      final body = jsonDecode(writes(h).single.split(' ').skip(2).join(' '));
      expect(writes(h).single, startsWith('POST /v1/curation/packs '));
      expect(body, {
        'title': 'Hora do banho',
        'video_ids': ['bichos-baleia', 'bichos-abelha', 'bichos-coelho'],
        'cover_video_id': 'bichos-abelha',
        'theme': 'bichos',
      });
      expect(find.widgetWithText(Notice, packSent), findsOneWidget);
      await tapOn(tester, find.text('Voltar para pacotinhos'));
      expect(h.location(tester), '/pacotinhos');
    });

    testWidgets('"Sem tema" sends no theme', (tester) async {
      final h = await composer(tester);
      await pick(tester, ['Abelha', 'Baleia', 'Coelho']);
      await tapOn(tester, find.widgetWithText(SelectableRow, 'Sem tema'));
      await name(tester, 'Hora do banho');
      await tapOn(tester, send);

      expect(writes(h).single, isNot(contains('"theme"')));
    });

    for (final (reason, section) in [
      ('title', 'Nome do pacotinho'),
      ('duration', 'Vídeos'),
      ('not_approved', 'Vídeos'),
      ('cover', 'Capa'),
    ]) {
      testWidgets('pack_invalid $reason is worded at "$section"', (
        tester,
      ) async {
        await composer(
          tester,
          write: (_) => problem(422, 'pack_invalid', extra: {'reason': reason}),
        );
        await pick(tester, ['Abelha', 'Baleia', 'Coelho']);
        await name(tester, 'Hora do banho');
        await tapOn(tester, send);

        final message = invalidMessage(reason);
        expect(find.text(message), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(message)).dy,
          greaterThan(tester.getTopLeft(find.text(section).first).dy),
        );
        expect(find.byType(Notice), findsNothing);
      });
    }
  });

  group('recomposing', () {
    testWidgets('opens prefilled with the current round, and sends the new '
        'version', (tester) async {
      final h = await composer(
        tester,
        initial: '/pacotinhos/p1/mudar',
        pack: (id) => json(
          200,
          packOf(id, 'Hora do banho', state: 'approved', theme: 'musica'),
        ),
        write: (_) => json(200, packOf('p1', 'Hora do banho')),
      );

      expect(find.text('Mudar pacotinho'), findsOneWidget);
      expect(find.text('1. Galinha Pintadinha'), findsOneWidget);
      expect(find.text('3. Pato Pateta'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Nome do pacotinho'),
            )
            .controller!
            .text,
        'Hora do banho',
      );
      expect(
        tester
            .widget<SelectableRow>(find.widgetWithText(SelectableRow, 'Música'))
            .selected,
        isTrue,
      );

      await tapOn(tester, find.byTooltip('Descer Galinha Pintadinha'));
      await tapOn(tester, send);

      expect(writes(h).single, startsWith('PUT /v1/curation/packs/p1 '));
      expect(writes(h).single, contains('"video_ids":["v2","v1","v3"]'));
      expect(find.widgetWithText(Notice, versionSent), findsOneWidget);
    });

    testWidgets('state_conflict goes back to the list, saying it was '
        'removed', (tester) async {
      final h = await composer(
        tester,
        initial: '/pacotinhos/p1/mudar',
        write: (_) => problem(409, 'state_conflict'),
      );

      await tapOn(tester, send);

      expect(h.location(tester), '/pacotinhos');
      expect(
        find.widgetWithText(Notice, 'Esse pacotinho foi removido.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the picker opened directly goes back to the composer', (
    tester,
  ) async {
    final h = await composer(tester, initial: '/pacotinhos/novo/videos');

    expect(h.location(tester), '/pacotinhos/novo');
  });
}

/// The cover choice read "Capa: [title]".
Finder coverOf(String title) => find.byWidgetPredicate(
  (w) => w is ChoiceTarget && w.label == 'Capa: $title',
);

/// The title of the cover choice that reads selected.
String coverChosen(WidgetTester tester) {
  for (final title in ['Abelha', 'Baleia', 'Coelho']) {
    final f = coverOf(title);
    if (f.evaluate().isNotEmpty && tester.widget<ChoiceTarget>(f).selected) {
      return title;
    }
  }
  return '';
}

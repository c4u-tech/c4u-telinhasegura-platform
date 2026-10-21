import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/copy.dart';
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/auth/api_error.dart';
import 'package:telinha_segura/curation/curator_terms_screen.dart';
import 'package:telinha_segura/curation/queue_screen.dart' show emptyQueue;
import 'package:telinha_segura/legal/legal_links.dart' show kCurationUrl;
import 'package:telinha_segura/shell/routes.dart';

import '../access/harness.dart';
import '../family/fixtures.dart';
import 'fixtures.dart';

/// A curator who has not accepted the curator terms: every curation read
/// answers `declaration_required` until "Aceito" goes through.
Future<Harness> awaitingTerms(
  WidgetTester tester, {
  String initial = '/curadoria',
  FutureOr<http.Response> Function(http.Request)? accept,
}) async {
  var declared = false;
  final h =
      Harness(
          signedIn: true,
          api: curatorApi(
            queue: (_) =>
                declared ? queuePage([]) : problem(403, 'declaration_required'),
            video: (id) => declared
                ? detailOf(queuedJson(id, 'Baby Shark'))
                : problem(403, 'declaration_required'),
            declaration: () => json(200, termsJson()),
            accept: (req) async {
              final answer =
                  await (accept?.call(req) ??
                      json(200, termsJson(accepted: true)));
              declared = answer.statusCode == 200;
              return answer;
            },
          ),
        )
        ..family = ownerFamily
        ..roles = ['curator'];
  await h.pump(tester, initial: initial);
  return h;
}

Future<void> agree(WidgetTester tester) async {
  await tester.ensureVisible(
    find.widgetWithText(FilledButton, curatorTermsAccept),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, curatorTermsAccept));
  await tester.pumpAndSettle();
}

void main() {
  namingAndLink();
  test('the terms route and where "Aceito" may return', () {
    expect(Routes.curatorTerms, '/curadoria/termo');
    expect(
      Routes.curatorTermsFor(then: '/curadoria'),
      '/curadoria/termo?depois=%2Fcuradoria',
    );
    for (final ok in ['/curadoria', '/curadoria/v1', '/pacotinhos/p1']) {
      expect(Routes.curatorTermsReturn(ok), ok, reason: ok);
    }
    for (final bad in [
      null,
      '',
      'https://example.com/curadoria',
      '//example.com/curadoria',
      '/admin',
      '/curadoria/termo',
      '/curadoria/../admin',
      'curadoria',
      '/curadoria/%2e%2e/admin',
      '/curadoria//example.com',
      '/curadoria#x',
      r'\\example.com',
      '/curadoriax',
      'javascript:alert(1)',
    ]) {
      expect(Routes.curatorTermsReturn(bad), '/curadoria', reason: '$bad');
    }
  });

  testWidgets('the queue without the terms shows them; "Aceito" sends the '
      'version shown and returns to the queue', (tester) async {
    final h = await awaitingTerms(tester);

    expect(h.location(tester), '/curadoria/termo?depois=%2Fcuradoria');
    expect(find.text(curatorTermsLead), findsOneWidget);
    expect(find.text(termsJson()['text']! as String), findsOneWidget);
    await agree(tester);

    expect(h.actions.where((a) => a.startsWith('POST')), [
      'POST /v1/curation/declaration {"version":"2026-10-20"}',
    ]);
    expect(h.location(tester), '/curadoria');
    expect(find.text(emptyQueue), findsOneWidget);
  });

  testWidgets('a review opened directly comes back to that review', (
    tester,
  ) async {
    final h = await awaitingTerms(tester, initial: '/curadoria/v1');

    expect(h.location(tester), '/curadoria/termo?depois=%2Fcuradoria%2Fv1');
    await agree(tester);

    expect(h.location(tester), '/curadoria/v1');
  });

  testWidgets('declaration_outdated reads the terms again and says why', (
    tester,
  ) async {
    final h = await awaitingTerms(
      tester,
      accept: (_) => problem(409, 'declaration_outdated'),
    );

    await agree(tester);

    expect(
      find.widgetWithText(
        ErrorNote,
        Copy.forError(
          const ApiError(status: 409, code: 'declaration_outdated'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      h.actions.where((a) => a == 'GET /v1/curation/declaration'),
      hasLength(2),
    );
    expect(h.location(tester), startsWith('/curadoria/termo'));
  });

  testWidgets('terms already accepted go straight back', (tester) async {
    final h = Harness(signedIn: true, api: curatorApi())
      ..family = ownerFamily
      ..roles = ['curator'];
    await h.pump(tester, initial: '/curadoria/termo?depois=%2Fcuradoria');

    expect(h.location(tester), '/curadoria');
  });

  for (final bad in ['%2F%2Fexample.com', '%2Fadmin']) {
    testWidgets('accepted terms never return to $bad', (tester) async {
      final h = Harness(signedIn: true, api: curatorApi())
        ..family = ownerFamily
        ..roles = ['curator'];
      await h.pump(tester, initial: '/curadoria/termo?depois=$bad');

      expect(h.location(tester), '/curadoria');
    });
  }

  testWidgets('"Aceito" never returns outside the curation', (tester) async {
    final h = await awaitingTerms(
      tester,
      initial: '/curadoria/termo?depois=%2Fadmin',
    );
    await agree(tester);

    expect(h.location(tester), '/curadoria');
  });

  testWidgets('the pacotinhos without the terms come back to the pacotinhos', (
    tester,
  ) async {
    var declared = false;
    final curator = curatorApi(
      declaration: () => json(200, termsJson()),
      accept: (_) {
        declared = true;
        return json(200, termsJson(accepted: true));
      },
    );
    final packs = packApi(
      list: (_) =>
          declared ? packPage([]) : problem(403, 'declaration_required'),
    );
    final h =
        Harness(
            signedIn: true,
            api: (req) => req.url.path == '/v1/curation/declaration'
                ? curator(req)
                : packs(req),
          )
          ..family = ownerFamily
          ..roles = ['curator'];
    await h.pump(tester, initial: '/pacotinhos');

    expect(h.location(tester), '/curadoria/termo?depois=%2Fpacotinhos');
    await agree(tester);
    expect(h.location(tester), '/pacotinhos');
  });

  testWidgets('declaration_required from the terms calls is a failure, not a '
      'loop', (tester) async {
    final read =
        Harness(
            signedIn: true,
            api: curatorApi(
              declaration: () => problem(403, 'declaration_required'),
            ),
          )
          ..family = ownerFamily
          ..roles = ['curator'];
    await read.pump(tester, initial: '/curadoria/termo?depois=%2Fcuradoria');

    expect(read.location(tester), '/curadoria/termo?depois=%2Fcuradoria');
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('declaration_required on "Aceito" stays on the terms', (
    tester,
  ) async {
    final h = await awaitingTerms(
      tester,
      accept: (_) => problem(403, 'declaration_required'),
    );
    await agree(tester);

    expect(h.location(tester), startsWith('/curadoria/termo'));
    expect(find.widgetWithText(FilledButton, curatorTermsAccept), findsOne);
  });
}

void namingAndLink() {
  testWidgets('the terms are called "termo do curador", as on the site', (
    tester,
  ) async {
    await awaitingTerms(tester);

    expect(find.text('Termo do curador'), findsWidgets);
    expect(curatorTermsLead, contains('termo do curador'));
    for (final code in ['declaration_required', 'declaration_outdated']) {
      expect(
        Copy.forError(ApiError(status: 409, code: code)),
        contains('termo do curador'),
        reason: code,
      );
    }
  });

  test('no screen calls them "termo da curadoria"', () {
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      expect(
        f.readAsStringSync().toLowerCase().contains('termo da curadoria'),
        isFalse,
        reason: f.path,
      );
    }
  });

  testWidgets('the terms link the published criteria, read as a link', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = await awaitingTerms(tester);

    await tester.ensureVisible(find.text(curationCriteriaTitle));
    await tester.pumpAndSettle();
    expect(
      find.semantics.byPredicate(
        (n) => n.label == curationCriteriaTitle && n.flagsCollection.isLink,
      ),
      findsOne,
    );
    await tester.tap(find.text(curationCriteriaTitle));
    await tester.pumpAndSettle();

    expect(h.links.opened, [kCurationUrl]);
    expect(h.location(tester), '/curadoria/termo?depois=%2Fcuradoria');
    semantics.dispose();
  });
}

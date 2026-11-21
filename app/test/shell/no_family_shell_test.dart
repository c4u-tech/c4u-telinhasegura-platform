// A signed-in adult without a family yet gets the same navigation as
// everyone else, and the start of a family on Início and on Família.
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:telinha_segura/access/widgets.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/design/display_title.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/family_start.dart';
import 'package:telinha_segura/family/inicio.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/shell/guardian_shell.dart';

import '../access/a11y_test.dart' show invitationsFor;
import '../access/harness.dart';
import '../family/fixtures.dart';
import 'guardian_shell_test.dart' show labels, selected, wide;

/// The app at [path] for a signed-in account with no family.
Future<Harness> noFamilyAt(
  WidgetTester tester,
  String path, {
  List<String> roles = const [],
  Size size = const Size(390, 844),
}) async {
  final h = Harness(signedIn: true)
    ..family = null
    ..roles = roles;
  await h.pump(tester, initial: path, size: size);
  return h;
}

String title(WidgetTester tester) =>
    tester.widget<DisplayTitle>(find.byType(DisplayTitle)).text;

void main() {
  group('the navigation without a family', () {
    testWidgets('a phone shows the bar on Início: Início, Família, Conta', (
      tester,
    ) async {
      await noFamilyAt(tester, '/');

      expect(find.byType(ShellBar), findsOneWidget);
      expect(labels(tester), ['Início', 'Família', 'Conta']);
      expect(selected(tester), Destination.inicio);
    });

    testWidgets('Equipe joins for a role holder', (tester) async {
      await noFamilyAt(tester, '/', roles: ['curator']);

      expect(labels(tester), ['Início', 'Família', 'Conta', 'Equipe']);
    });

    testWidgets('a wide window shows the rail', (tester) async {
      await noFamilyAt(tester, '/', size: wide);

      expect(find.byType(InkRail), findsOneWidget);
      expect(labels(tester), ['Início', 'Família', 'Conta']);
    });

    testWidgets('Conta opens as for anyone, the navigation kept', (
      tester,
    ) async {
      final h = await noFamilyAt(tester, '/');

      await tester.tap(find.widgetWithText(DestinationTile, 'Conta'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/conta');
      expect(selected(tester), Destination.conta);
      expect(find.text('Sair da conta'), findsOneWidget);
    });

    testWidgets('a family\'s inner screen still sends home', (tester) async {
      final h = await noFamilyAt(tester, '/familia/criancas');

      expect(h.location(tester), '/');
    });
  });

  group('Início without a family', () {
    testWidgets('the greeting, then the start of a family as one module, '
        'and no doors in the page', (tester) async {
      await noFamilyAt(tester, '/', roles: ['curator']);

      expect(title(tester), greeting(clock.now()));
      final module = find.byType(ChildCard);
      expect(module, findsOneWidget);
      for (final inside in [
        find.textContaining('Comece a sua família'),
        find.byType(CapacityRow),
        find.widgetWithText(PrimaryButton, 'Começar minha família'),
        find.widgetWithText(OutlinedButton, 'Tenho um convite'),
      ]) {
        expect(find.descendant(of: module, matching: inside), findsWidgets);
      }
      expect(find.byType(CapacityRow), findsNWidgets(2));
      expect(find.byType(DoorRow), findsNothing);
      expect(find.widgetWithText(QuietAction, 'Sair da conta'), findsNothing);
    });

    testWidgets('on a wide window, the module stands where the home\'s first '
        'child card does: under the title, in the first of two columns', (
      tester,
    ) async {
      await noFamilyAt(tester, '/', size: const Size(1280, 800));
      final title = tester.getRect(find.byType(DisplayTitle));
      final module = tester.getRect(find.byType(ChildCard));

      // The home's two columns, centred beside the rail, as with children.
      const rail = ShellSizes.railInset + ShellSizes.railWidth;
      const pair = 2 * FieldSizes.columnMaxWidth + Space.xl;
      expect(title.left, rail + (1280 - rail - pair) / 2);
      // A child's card there: half of two task columns and their gap.
      expect(module.left, title.left);
      expect(module.width, FieldSizes.columnMaxWidth);
    });

    testWidgets('once started, the usual home comes without a restart', (
      tester,
    ) async {
      final h = Harness(
        signedIn: true,
        api: (req) => req.method == 'POST' && req.url.path == '/v1/family'
            ? json(201, familyWith([]))
            : http.Response('', 204),
      )..family = null;
      await h.pump(tester, initial: '/');
      h.family = familyWith([]);

      await tester.tap(find.text('Começar minha família'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(FamilyStart), findsNothing);
      expect(find.byType(Inicio), findsOneWidget);
      expect(find.byType(ShellBar), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('Família without a family', () {
    testWidgets('shows the same start, under its own title, Família '
        'selected', (tester) async {
      final h = await noFamilyAt(tester, '/familia');

      expect(h.location(tester), '/familia');
      expect(selected(tester), Destination.familia);
      expect(title(tester), 'Sua família');
      expect(find.byType(FamilyStart), findsOneWidget);
      expect(find.text('Começar minha família'), findsOneWidget);
    });

    testWidgets('with an invitation waiting, lists it to accept, as Início '
        'does', (tester) async {
      final h = Harness(
        signedIn: true,
        api: invitationsFor(['carla@example.com']),
      )..family = null;
      await h.pump(tester, initial: '/familia');

      expect(h.location(tester), '/familia');
      expect(find.text(addressBreaks('carla@example.com')), findsOneWidget);
      expect(find.text('Entrar na família'), findsOneWidget);
      expect(find.text('Tenho um convite'), findsNothing);
    });

    testWidgets('accepting the invitation there opens the family', (
      tester,
    ) async {
      late final Harness h;
      h = Harness(
        signedIn: true,
        api: (req) {
          if (req.method == 'POST' && req.url.path.contains('/invitations')) {
            h.family = ownerFamily;
            return json(200, ownerFamily);
          }
          return invitationsFor(['carla@example.com'])(req);
        },
      )..family = null;
      await h.pump(tester, initial: '/familia');

      await tester.tap(find.text('Entrar na família'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia');
      expect(find.widgetWithText(DoorRow, 'Crianças'), findsOneWidget);
    });

    testWidgets('on a wide window, alone beside the rail', (tester) async {
      final h = await noFamilyAt(
        tester,
        '/familia',
        size: const Size(1280, 800),
      );

      expect(h.location(tester), '/familia');
      expect(find.byType(FamilyStart), findsOneWidget);
      expect(find.byType(InkRail), findsOneWidget);
    });

    testWidgets('started here, the family\'s first steps open', (tester) async {
      final h = Harness(
        signedIn: true,
        api: (req) => req.method == 'POST' && req.url.path == '/v1/family'
            ? json(201, familyWith([]))
            : http.Response('', 204),
      )..family = null;
      await h.pump(tester, initial: '/familia');
      h.family = familyWith([]);

      await tester.tap(find.text('Começar minha família'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/comecar');
    });
  });
}

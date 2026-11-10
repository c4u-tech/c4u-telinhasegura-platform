import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:telinha_segura/design/band_transition.dart';
import 'package:telinha_segura/design/display_title.dart';
import 'package:telinha_segura/design/field_layout.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/shell/guardian_shell.dart';

import '../access/harness.dart';
import '../design/pump.dart' show brandAssets;
import '../family/fixtures.dart';

const phone = Size(390, 844);
const wide = Size(1280, 800);

/// The app at [path] for a signed-in member of the owner's family, with
/// the platform [roles] given.
Future<Harness> shellAt(
  WidgetTester tester,
  String path, {
  List<String> roles = const [],
  Size size = phone,
  double textScale = 1,
  void Function(Harness)? setUp,
}) async {
  final h = Harness(signedIn: true)
    ..family = ownerFamily
    ..roles = roles;
  setUp?.call(h);
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  return h;
}

List<String> labels(WidgetTester tester) => [
  for (final d in tester.widgetList<DestinationTile>(
    find.byType(DestinationTile),
  ))
    d.destination.label,
];

Destination? selected(WidgetTester tester) => tester
    .widgetList<DestinationTile>(find.byType(DestinationTile))
    .where((d) => d.selected)
    .map((d) => d.destination)
    .singleOrNull;

void main() {
  group('the bottom navigation on a narrow window', () {
    for (final path in ['/', '/familia', '/conta']) {
      testWidgets('shows Início, Família and Conta on $path', (tester) async {
        await shellAt(tester, path);

        expect(find.byType(ShellBar), findsOneWidget);
        expect(find.byType(InkRail), findsNothing);
        expect(labels(tester), ['Início', 'Família', 'Conta']);
      });
    }

    for (final roles in [
      ['curator'],
      ['moderator'],
      ['admin'],
    ]) {
      testWidgets('adds Equipe for $roles', (tester) async {
        await shellAt(tester, '/', roles: roles);

        expect(labels(tester), ['Início', 'Família', 'Conta', 'Equipe']);
      });
    }

    testWidgets('shows on /equipe for a staff account', (tester) async {
      final h = await shellAt(tester, '/equipe', roles: ['curator']);

      expect(h.location(tester), '/equipe');
      expect(find.byType(ShellBar), findsOneWidget);
      expect(selected(tester), Destination.equipe);
    });

    for (final (path, roles) in [
      ('/familia/criancas', <String>[]),
      ('/familia/criancas/m1', <String>[]),
      ('/modo-crianca', <String>[]),
      ('/conta/email', <String>[]),
      ('/sugestoes', <String>[]),
      ('/sugestoes/nova', <String>[]),
      ('/curadoria', ['curator']),
    ]) {
      testWidgets('hides on $path, a screen other than a root', (tester) async {
        final h = await shellAt(tester, path, roles: roles);

        expect(h.location(tester), path);
        expect(find.byType(ShellBar), findsNothing);
        expect(find.byType(DestinationTile), findsNothing);
      });
    }

    for (final (from, label, to) in [
      ('/', 'Família', '/familia'),
      ('/familia', 'Conta', '/conta'),
      ('/conta', 'Início', '/'),
      ('/', 'Equipe', '/equipe'),
    ]) {
      testWidgets('tapping $label on $from goes to $to and marks it', (
        tester,
      ) async {
        final h = await shellAt(tester, from, roles: ['admin']);

        await tester.tap(find.widgetWithText(DestinationTile, label));
        await tester.pumpAndSettle();

        expect(h.location(tester), to);
        expect(selected(tester)?.label, label);
      });
    }

    testWidgets('each destination is a labelled button with its selected '
        'state and a 48 dp target', (tester) async {
      final semantics = tester.ensureSemantics();
      await shellAt(tester, '/familia', roles: ['curator']);

      for (final (label, isSelected) in [
        ('Início', false),
        ('Família', true),
        ('Conta', false),
        ('Equipe', false),
      ]) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label).last),
          isSemantics(
            label: label,
            isButton: true,
            hasSelectedState: true,
            isSelected: isSelected,
            hasTapAction: true,
          ),
          reason: label,
        );
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });

    for (final ground in ['light', 'dark']) {
      testWidgets('holds four destinations at 200 % text on a 360 dp phone, '
          '$ground', (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = ground == 'dark'
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await shellAt(
          tester,
          '/',
          roles: ['admin'],
          size: const Size(360, 780),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(labels(tester), ['Início', 'Família', 'Conta', 'Equipe']);
        for (final tile in find.byType(DestinationTile).evaluate()) {
          final size = tester.getSize(find.byWidget(tile.widget));
          expect(size.height, greaterThanOrEqualTo(48));
          expect(size.width, greaterThanOrEqualTo(48));
        }
      });
    }

    testWidgets('the selected destination is cut as a screen module in the '
        'action colour, never a pill', (tester) async {
      await shellAt(tester, '/');

      final module = tester.widget<Container>(
        find.descendant(
          of: find.widgetWithText(DestinationTile, 'Início'),
          matching: find.byKey(DestinationTile.indicatorKey),
        ),
      );
      final box = module.decoration! as BoxDecoration;
      final size = tester.getSize(
        find.descendant(
          of: find.widgetWithText(DestinationTile, 'Início'),
          matching: find.byKey(DestinationTile.indicatorKey),
        ),
      );
      expect(box.color, Palette.light.action);
      expect(size, const Size(ShellSizes.indicatorWidth, ShellSizes.indicator));
      expect(
        box.borderRadius,
        BorderRadius.circular(ShellSizes.indicator * Radii.screenRatio),
      );
      final idle = tester.widget<Container>(
        find.descendant(
          of: find.widgetWithText(DestinationTile, 'Conta'),
          matching: find.byKey(DestinationTile.indicatorKey),
        ),
      );
      expect((idle.decoration! as BoxDecoration).color, isNull);
    });

    testWidgets('the bar sits on the ground under a reed hairline', (
      tester,
    ) async {
      await shellAt(tester, '/');

      final bar = tester.widget<DecoratedBox>(find.byKey(ShellBar.surfaceKey));
      final box = bar.decoration as BoxDecoration;
      expect(box.color, Palette.light.ground);
      expect(
        box.border,
        Border(
          top: BorderSide(color: Palette.light.outline.withValues(alpha: .5)),
        ),
      );
      expect(box.boxShadow, isNull);
    });
  });

  group('the ink rail on a wide window', () {
    for (final path in ['/', '/familia', '/familia/criancas', '/conta/email']) {
      testWidgets('holds the lockup and the destinations on $path, with no '
          '46 % panel', (tester) async {
        await shellAt(tester, path, size: wide);

        expect(find.byType(InkRail), findsOneWidget);
        expect(find.byType(ShellBar), findsNothing);
        expect(labels(tester), ['Início', 'Família', 'Conta']);
        expect(
          find.descendant(
            of: find.byType(InkRail),
            matching: find.bySemanticsLabel('Telinha Segura'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(FieldLayout.panelKey), findsNothing);
        expect(find.byType(FieldLayout), findsOneWidget);
      });
    }

    testWidgets('the rail centres the reversed wordmark under the head, '
        'at least 22 tall, with the destinations at the start below', (
      tester,
    ) async {
      await shellAt(tester, '/', size: wide);

      final rail = find.byType(InkRail);
      expect(brandAssets(tester, rail).map((a) => a.$1), [
        'assets/brand/telinha-segura-wordmark-reversed.svg',
      ]);
      final wordmark = find.descendant(
        of: rail,
        matching: find.byType(SvgPicture),
      );
      final head = find.descendant(
        of: rail,
        matching: find.byType(PeekingHead),
      );
      expect(tester.getSize(wordmark).height, greaterThanOrEqualTo(22));
      expect(
        tester.getCenter(wordmark).dx,
        moreOrLessEquals(tester.getCenter(head).dx, epsilon: 2),
      );
      final first = tester.getRect(find.byType(DestinationTile).first);
      expect(first.top, greaterThan(tester.getRect(wordmark).bottom));
      expect(first.left, lessThan(tester.getRect(wordmark).left));
    });

    testWidgets('the rail is the ink field, cut at the mark radius, with no '
        'shadow', (tester) async {
      await shellAt(tester, '/', size: wide);

      final field = tester.widget<DecoratedBox>(find.byKey(InkRail.fieldKey));
      final box = field.decoration as BoxDecoration;
      expect(box.color, Palette.light.field);
      expect(box.borderRadius, BorderRadius.circular(10 * ShellSizes.railUnit));
      expect(box.boxShadow, isNull);
      expect(
        tester.getRect(find.byKey(InkRail.fieldKey)),
        guardianBand(wide, EdgeInsets.zero).outerRect,
      );
    });

    testWidgets('a screen outside the shell keeps its 46 % panel', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester, initial: '/entrar', size: wide);

      expect(find.byType(InkRail), findsNothing);
      expect(find.byKey(FieldLayout.panelKey), findsOneWidget);
    });

    for (final (path, roles, expected) in [
      ('/familia/criancas/m1', <String>[], Destination.familia),
      ('/familia/tempo/m1/mais', <String>[], Destination.familia),
      ('/modo-crianca', <String>[], Destination.familia),
      ('/curadoria', ['curator'], Destination.equipe),
      ('/admin', ['admin'], Destination.equipe),
      ('/conta/email', <String>[], Destination.conta),
      ('/sugestoes', <String>[], Destination.inicio),
      ('/', <String>[], Destination.inicio),
    ]) {
      testWidgets('$path selects ${expected.label}', (tester) async {
        final h = await shellAt(tester, path, roles: roles, size: wide);

        expect(h.location(tester), path);
        expect(selected(tester), expected);
      });
    }

    testWidgets('a task screen\'s back control stays, beside the content', (
      tester,
    ) async {
      final h = await shellAt(tester, '/familia/criancas', size: wide);

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia');
    });

    testWidgets('every title stands at one place beside the rail, root or '
        'task, so switching destinations moves none', (tester) async {
      Offset? anchor;
      await shellAt(tester, '/', size: wide, roles: ['curator']);
      for (final path in [
        '/',
        '/familia',
        '/conta',
        '/equipe',
        '/familia/criancas',
        '/conta/email',
      ]) {
        GoRouter.of(tester.element(find.byType(InkRail))).go(path);
        await tester.pumpAndSettle();
        final title = tester.getTopLeft(find.byType(DisplayTitle));
        anchor ??= title;
        expect(title, anchor, reason: path);
      }
      // Top and start, not centred in the space beside the rail.
      expect(anchor!.dy, lessThan(200));
      expect(
        anchor.dx,
        ShellSizes.railInset + ShellSizes.railWidth + Space.xxxl,
      );
    });

    testWidgets('a task\'s back control stands at the column\'s start, '
        'right above the title', (tester) async {
      await shellAt(tester, '/familia/criancas', size: wide);

      final back = tester.getRect(find.byTooltip('Voltar'));
      final arrow = tester.getRect(find.byIcon(Icons.arrow_back_rounded));
      final title = tester.getRect(find.byType(DisplayTitle));
      expect(back.bottom, lessThanOrEqualTo(title.top));
      expect(title.top - back.bottom, lessThanOrEqualTo(Space.md));
      // The arrow on the column's edge: the button's own inset stands
      // outside it.
      expect(arrow.left, closeTo(title.left, 0.5));
    });

    testWidgets('a destination root has no back control', (tester) async {
      await shellAt(tester, '/familia', size: wide);

      expect(find.byTooltip('Voltar'), findsNothing);
    });
  });

  group('the destination of a path', () {
    for (final (path, expected) in [
      ('/', Destination.inicio),
      ('/sugestoes', Destination.inicio),
      ('/sugestoes/nova', Destination.inicio),
      ('/familia', Destination.familia),
      ('/familia/criancas/x', Destination.familia),
      ('/familia/videos/m1/v1', Destination.familia),
      ('/modo-crianca/entregar', Destination.familia),
      ('/conta', Destination.conta),
      ('/conta/email', Destination.conta),
      ('/equipe', Destination.equipe),
      ('/curadoria', Destination.equipe),
      ('/pacotinhos/novo', Destination.equipe),
      ('/admin/equipe', Destination.equipe),
      ('/moderacao/retidos', Destination.equipe),
    ]) {
      test('$path is ${expected.label}', () {
        expect(Destination.of(path), expected);
      });
    }

    test('only the four roots are roots', () {
      expect(
        [
          for (final p in ['/', '/familia', '/conta', '/equipe', '/sugestoes'])
            Destination.isRoot(p),
        ],
        [true, true, true, true, false],
      );
    });
  });

  group('outside the shell', () {
    final states = <String, void Function(Harness)>{
      'no family': (h) => h.family = null,
      'the email unverified': (h) => h
        ..family = null
        ..unverified = true,
      'the family failing to load': (h) =>
          h.familyRead = () => problem(503, 'unavailable'),
      'a suspended account': (h) => h.status = 'suspended',
    };
    for (final MapEntry(key: state, value: setUp) in states.entries) {
      for (final size in [phone, wide]) {
        testWidgets('with $state the home shows no navigation at '
            '${size.width}', (tester) async {
          await shellAt(tester, '/', size: size, setUp: setUp);

          expect(find.byType(ShellBar), findsNothing);
          expect(find.byType(InkRail), findsNothing);
          expect(find.byType(DestinationTile), findsNothing);
        });
      }
    }

    testWidgets('with no family, /conta keeps its back to the home', (
      tester,
    ) async {
      final h = await shellAt(tester, '/conta', setUp: (h) => h.family = null);

      expect(find.byType(ShellBar), findsNothing);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/');
    });

    testWidgets('terms pending show the terms screen without the shell', (
      tester,
    ) async {
      final h = await shellAt(
        tester,
        '/',
        size: wide,
        setUp: (h) => h.termsAccepted = false,
      );

      expect(h.location(tester), '/termos');
      expect(find.byType(InkRail), findsNothing);
      expect(find.byKey(FieldLayout.panelKey), findsOneWidget);
    });

    testWidgets('an invitation link shows without the shell', (tester) async {
      final h = await shellAt(tester, '/convite?token=t', size: wide);

      expect(Uri.parse(h.location(tester)).path, '/convite');
      expect(find.byType(InkRail), findsNothing);
    });

    testWidgets('signed out, the entry shows without the shell', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester, initial: '/', size: wide);

      expect(h.location(tester), '/entrar');
      expect(find.byType(InkRail), findsNothing);
      expect(find.byType(ShellBar), findsNothing);
    });
  });

  testWidgets('the router keeps one shell across the destinations', (
    tester,
  ) async {
    await shellAt(tester, '/', size: wide);
    final shell = tester.state(find.byType(GuardianShell));

    GoRouter.of(tester.element(find.byType(InkRail))).go('/familia');
    await tester.pumpAndSettle();

    expect(tester.state(find.byType(GuardianShell)), same(shell));
    expect(context(tester).palette.field, BrandColors.ink);
  });
}

BuildContext context(WidgetTester tester) =>
    tester.element(find.byType(InkRail));

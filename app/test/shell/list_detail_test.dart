import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:telinha_segura/design/display_title.dart';
import 'package:telinha_segura/family/children_screen.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/family/widgets.dart';
import 'package:telinha_segura/shell/guardian_shell.dart';
import 'package:telinha_segura/shell/list_detail.dart';
import 'package:telinha_segura/shell/router.dart' show staffFirstItem;

import '../access/harness.dart';
import '../account/sessions_screen_test.dart'
    show atNow, endActions, sessionsScreen;
import '../family/child_page_test.dart' show pageApi;
import '../family/fixtures.dart';

const phone = Size(412, 915);
const mid = Size(1000, 800);

/// A Galaxy Tab S9 FE in landscape: 2304 × 1440 px at a density of 1.75.
const tablet = Size(1317, 823);

/// The rail's share of a wide window: its field and the inset before it.
const railShare = ShellSizes.railInset + ShellSizes.railWidth;

/// The app at [path] for the owner of a family with Lia, whose page reads
/// its day and videos, with the platform [roles] given.
Future<Harness> appAt(
  WidgetTester tester,
  String path, {
  Size size = tablet,
  double textScale = 1,
  List<String> roles = const [],
  Brightness brightness = Brightness.light,
}) async {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  late final Harness h;
  h = Harness(signedIn: true, api: pageApi(() => h))
    ..family = familyWith([minorJson('m1', 'Lia')])
    ..roles = roles;
  await h.pump(tester, initial: path, size: size, textScale: textScale);
  return h;
}

Finder get listPane => find.byKey(ListDetail.listKey);
Finder get detailPane => find.byKey(ListDetail.detailKey);

Finder inList(Finder f) => find.descendant(of: listPane, matching: f);
Finder inDetail(Finder f) => find.descendant(of: detailPane, matching: f);

Finder titled(String title) => find.widgetWithText(DisplayTitle, title);

Finder door(String title) => find.widgetWithText(DoorRow, title);

/// The one row of the list pane shown as chosen.
String? chosen(WidgetTester tester) => tester
    .widgetList<DoorRow>(inList(find.byType(DoorRow)))
    .where((d) => d.selected)
    .map((d) => d.title)
    .singleOrNull;

void go(WidgetTester tester, String path) =>
    GoRouter.of(tester.element(find.byType(InkRail))).go(path);

Future<void> resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

void main() {
  test('the tablet in landscape reaches the list-detail threshold, with '
      'room for the list and a 400 px detail', () {
    expect(tablet.width, greaterThanOrEqualTo(ShellSizes.listDetailBreakpoint));
    expect(
      ShellSizes.listDetailBreakpoint,
      greaterThan(FieldSizes.wideBreakpoint),
    );
    final detail =
        ShellSizes.listDetailBreakpoint - railShare - ShellSizes.listPaneWidth;
    expect(detail, greaterThanOrEqualTo(FieldSizes.columnMaxWidth + 72));
  });

  group('below the threshold', () {
    for (final size in [phone, mid]) {
      testWidgets('Família at ${size.width} shows no panes', (tester) async {
        await appAt(tester, '/familia', size: size);

        expect(listPane, findsNothing);
        expect(detailPane, findsNothing);
        expect(titled('Sua família'), findsOneWidget);
        expect(titled('Crianças'), findsNothing);
      });
    }

    testWidgets('a phone keeps the bar and the root alone', (tester) async {
      await appAt(tester, '/conta', size: phone);

      expect(find.byType(ShellBar), findsOneWidget);
      expect(titled('Sua conta'), findsOneWidget);
      // The phone's column, under its band, with its own side padding.
      expect(tester.getTopLeft(find.byType(DisplayTitle)).dx, Space.xl);
    });

    testWidgets('beside the rail every column stands centred on one axis, '
        'Início\'s band too', (tester) async {
      await appAt(tester, '/', size: mid);
      final axis = railShare + (mid.width - railShare) / 2;
      for (final path in [
        '/',
        '/familia',
        '/conta/email',
        '/familia/criancas',
      ]) {
        go(tester, path);
        await tester.pumpAndSettle();
        final title = tester.getRect(find.byType(DisplayTitle));
        expect(
          title.center.dx,
          moreOrLessEquals(axis, epsilon: 1),
          reason: path,
        );
      }
      go(tester, '/familia/criancas');
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(DisplayTitle)).width, 400);
    });
  });

  group('at the threshold and above', () {
    testWidgets('Família is a list pane beside the rail and a detail pane, '
        'divided by a reed hairline, with no card and no shadow', (
      tester,
    ) async {
      await appAt(tester, '/familia');

      final list = tester.getRect(listPane);
      final detail = tester.getRect(detailPane);
      expect(list.left, railShare);
      expect(list.width, ShellSizes.listPaneWidth);
      expect(detail.width, greaterThanOrEqualTo(400));
      expect(detail.right, tablet.width);
      final hairline = tester.widget<VerticalDivider>(
        find.byKey(ListDetail.hairlineKey),
      );
      expect(hairline.thickness, 1);
      expect(hairline.color, Palette.light.outline.withValues(alpha: .5));
      expect(
        tester.getRect(find.byKey(ListDetail.hairlineKey)).left,
        list.right,
      );
      expect(find.byType(Card), findsNothing);
      expect(
        find.byType(Material).evaluate().every((e) {
          final m = e.widget as Material;
          return m.elevation == 0;
        }),
        isTrue,
      );
    });

    testWidgets('on dark the hairline takes the night outline', (tester) async {
      await appAt(tester, '/familia', brightness: Brightness.dark);

      final hairline = tester.widget<VerticalDivider>(
        find.byKey(ListDetail.hairlineKey),
      );
      expect(hairline.color, Palette.dark.outline.withValues(alpha: .5));
      expect(chosen(tester), 'Crianças');
    });

    testWidgets('the titles of both panes stand on one line', (tester) async {
      await appAt(tester, '/familia');

      final list = tester.getRect(inList(find.byType(DisplayTitle)));
      final detail = tester.getRect(inDetail(find.byType(DisplayTitle)));
      expect(list.top, detail.top);
      expect(list.top, lessThan(200));
    });

    for (final (path, roles, list, item, title) in [
      ('/familia', <String>[], 'Sua família', 'Crianças', 'Crianças'),
      ('/conta', <String>[], 'Sua conta', 'E-⁠mail', 'Trocar o e-⁠mail'),
      ('/equipe', ['curator'], 'Equipe', 'Revisar vídeos', 'Revisar vídeos'),
      ('/equipe', ['admin'], 'Equipe', 'Vídeos retidos', 'Vídeos retidos'),
    ]) {
      testWidgets('$path for $roles opens $item on arrival, chosen in the '
          'list', (tester) async {
        final h = await appAt(tester, path, roles: roles);

        expect(h.location(tester), path);
        expect(inList(titled(list)), findsOneWidget);
        expect(inDetail(titled(title)), findsOneWidget);
        expect(chosen(tester), item);
        // The first level of the detail has no back: the list is beside it.
        expect(inDetail(find.byTooltip('Voltar')), findsNothing);
      });
    }

    testWidgets('the chosen row is announced as selected and carries the '
        'chosen stroke', (tester) async {
      final handle = tester.ensureSemantics();
      await appAt(tester, '/familia');

      final row = inList(door('Crianças'));
      expect(
        tester.getSemantics(row),
        isSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      final stroke = tester.widget<DecoratedBox>(
        find.descendant(of: row, matching: find.byKey(DoorRow.chosenKey)),
      );
      final shape = (stroke.decoration as ShapeDecoration).shape;
      expect((shape as RoundedRectangleBorder).side.width, 2.5);
      expect(shape.side.color, Palette.light.action);
      expect(
        tester.getSemantics(inList(door('Responsáveis'))),
        isNot(isSemantics(isSelected: true)),
      );
      handle.dispose();
    });

    testWidgets('choosing another item opens it in the detail, the list '
        'staying', (tester) async {
      final h = await appAt(tester, '/familia');

      await tester.tap(inList(door('Responsáveis')));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/responsaveis');
      expect(inList(titled('Sua família')), findsOneWidget);
      expect(inDetail(titled('Responsáveis')), findsOneWidget);
      expect(chosen(tester), 'Responsáveis');
    });

    testWidgets('a child\'s page and its tasks open in the detail, with the '
        'detail\'s own back, and system back walks the detail first', (
      tester,
    ) async {
      final h = await appAt(tester, '/familia');

      await tester.tap(inDetail(find.text('Lia')).first);
      await tester.pumpAndSettle();
      expect(h.location(tester), '/familia/criancas/m1');
      expect(inDetail(titled('Lia')), findsOneWidget);
      expect(chosen(tester), 'Crianças');
      expect(inDetail(find.byTooltip('Voltar')), findsOneWidget);

      final more = inDetail(find.text('Mais tempo hoje'));
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(h.location(tester), '/familia/tempo/m1/mais');
      expect(inList(titled('Sua família')), findsOneWidget);
      expect(chosen(tester), 'Crianças');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.location(tester), '/familia/tempo/m1');
      expect(inDetail(titled('Lia')), findsOneWidget);

      await tester.tap(inDetail(find.byTooltip('Voltar')));
      await tester.pumpAndSettle();
      expect(h.location(tester), '/familia/criancas');
      expect(inDetail(titled('Crianças')), findsOneWidget);
      expect(inDetail(find.byTooltip('Voltar')), findsNothing);
    });

    testWidgets('a curator\'s review opens in the detail beside Equipe', (
      tester,
    ) async {
      final h = await appAt(tester, '/curadoria', roles: ['curator']);

      expect(h.location(tester), '/curadoria');
      expect(inList(titled('Equipe')), findsOneWidget);
      expect(chosen(tester), 'Revisar vídeos');
      expect(inDetail(titled('Revisar vídeos')), findsOneWidget);
    });

    for (final path in [
      '/modo-crianca/pin',
      '/familia/excluir',
      '/conta/excluir',
    ]) {
      testWidgets('$path takes the whole content area beside the rail', (
        tester,
      ) async {
        await appAt(tester, path);

        expect(find.byType(InkRail), findsOneWidget);
        expect(listPane, findsNothing);
        final axis = railShare + (tablet.width - railShare) / 2;
        expect(
          tester.getRect(find.byType(DisplayTitle)).center.dx,
          moreOrLessEquals(axis, epsilon: 1),
        );
      });
    }

    for (final (path, item, title) in [
      ('/familia/criancas/m1', 'Crianças', 'Lia'),
      ('/familia/videos/m1', 'Crianças', 'Lia'),
      ('/familia/responsaveis', 'Responsáveis', 'Responsáveis'),
      ('/familia/convites', 'Convites', 'Convites'),
      ('/modo-crianca', 'Modo criança', 'Modo criança'),
      ('/conta/email', 'E-⁠mail', 'Trocar o e-⁠mail'),
      ('/conta/aparelhos', 'Aparelhos conectados', 'Aparelhos conectados'),
      ('/conta/dados', 'Seus dados', 'Seus dados'),
    ]) {
      testWidgets('a link to $path opens Família or Conta with $item chosen', (
        tester,
      ) async {
        final h = await appAt(tester, path);

        expect(h.location(tester), path);
        expect(listPane, findsOneWidget);
        expect(chosen(tester), item);
        expect(inDetail(titled(title)), findsOneWidget);
      });
    }

    testWidgets('rotating and resizing keep the item open', (tester) async {
      final h = await appAt(tester, '/familia/criancas/m1');
      expect(inDetail(titled('Lia')), findsOneWidget);

      await resize(tester, const Size(823, 1317));
      expect(h.location(tester), '/familia/criancas/m1');
      expect(listPane, findsNothing);
      expect(titled('Lia'), findsOneWidget);

      await resize(tester, mid);
      expect(titled('Lia'), findsOneWidget);
      expect(listPane, findsNothing);

      await resize(tester, tablet);
      expect(h.location(tester), '/familia/criancas/m1');
      expect(inDetail(titled('Lia')), findsOneWidget);
      expect(chosen(tester), 'Crianças');
    });

    testWidgets('Início stays one centred place, without panes', (
      tester,
    ) async {
      await appAt(tester, '/');

      expect(listPane, findsNothing);
      final axis = railShare + (tablet.width - railShare) / 2;
      expect(
        tester.getRect(find.byType(DisplayTitle)).center.dx,
        moreOrLessEquals(axis, epsilon: 1),
      );
    });

    testWidgets('focus moves from the list to the detail', (tester) async {
      await appAt(tester, '/familia');

      final rows = <String>[];
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus?.context;
        final row = focused?.findAncestorWidgetOfExactType<DoorRow>();
        if (row == null || focused == null) continue;
        final here = find.descendant(
          of: listPane,
          matching: find.byElementPredicate((e) => e == focused),
        );
        final pane = here.evaluate().isEmpty ? 'detail' : 'list';
        if (rows.lastOrNull != '$pane:${row.title}') {
          rows.add('$pane:${row.title}');
        }
      }
      // Tab goes round; from the list's first row, the whole list comes
      // before the detail.
      final from = rows.indexOf('list:Crianças');
      expect(rows.sublist(from, from + 5), [
        'list:Crianças',
        'list:Responsáveis',
        'list:Convites',
        'list:Modo criança',
        'detail:Lia',
      ]);
    });

    testWidgets('at 200 % text the panes hold without clipping, the list '
        'growing so no title breaks inside a word', (tester) async {
      await appAt(tester, '/familia/criancas/m1', textScale: 2);

      expect(tester.takeException(), isNull);
      expect(inDetail(titled('Lia')), findsOneWidget);
      // A third wider at 200 % than at 150 %, where the rows wrap only
      // between words.
      expect(
        tester.getSize(listPane).width,
        moreOrLessEquals(ShellSizes.listPaneWidth * 2 / 1.5),
      );
    });

    testWidgets('at a text size the window cannot hold beside a list, the '
        'place falls back to one column', (tester) async {
      final h = await appAt(
        tester,
        '/familia/criancas/m1',
        size: const Size(1200, 900),
        textScale: 2.5,
      );

      expect(h.location(tester), '/familia/criancas/m1');
      expect(listPane, findsNothing);
      expect(titled('Lia'), findsOneWidget);
    });
  });

  group('the list and its open item', () {
    /// What the platform was asked to do: closing the app is
    /// "SystemNavigator.pop".
    List<String> platformCalls(WidgetTester tester) {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return calls;
    }

    for (final (path, roles) in [
      ('/familia/criancas', <String>[]),
      ('/familia/responsaveis', <String>[]),
      ('/conta/email', <String>[]),
      ('/curadoria', ['curator']),
    ]) {
      testWidgets('one system back from $path leaves the place, as from '
          'its root on a phone', (tester) async {
        final h = await appAt(tester, path, roles: roles);
        final calls = platformCalls(tester);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(calls, contains('SystemNavigator.pop'));
        expect(h.location(tester), path);
      });
    }

    testWidgets('below an item\'s first level, system back still walks the '
        'detail', (tester) async {
      final h = await appAt(tester, '/familia/criancas/m1');
      final calls = platformCalls(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(calls, isNot(contains('SystemNavigator.pop')));
      expect(h.location(tester), '/familia/criancas');
    });

    for (final path in ['/familia', '/familia/criancas']) {
      testWidgets('on $path the open row does nothing', (tester) async {
        final h = await appAt(tester, path);

        await tester.tap(inList(door('Crianças')));
        await tester.pump();

        expect(h.location(tester), path);
        expect(find.byType(ChildrenScreen), findsOneWidget);
        // No page moved in over the open one.
        expect(
          find.byType(ChildrenScreen, skipOffstage: false),
          findsOneWidget,
        );
      });
    }

    testWidgets('deeper in the item, the open row returns to its first level', (
      tester,
    ) async {
      final h = await appAt(tester, '/familia/criancas/m1');

      await tester.tap(inList(door('Crianças')));
      await tester.pumpAndSettle();

      expect(h.location(tester), '/familia/criancas');
      expect(inDetail(titled('Crianças')), findsOneWidget);
    });

    testWidgets('ending a session beside the list counts again in the list', (
      tester,
    ) async {
      await atNow(() async {
        await sessionsScreen(tester, size: tablet);
        expect(
          find.descendant(
            of: inList(door('Aparelhos conectados')),
            matching: find.text('3 aparelhos'),
          ),
          findsOneWidget,
        );

        await tester.tap(inDetail(endActions).first);
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: inList(door('Aparelhos conectados')),
            matching: find.text('2 aparelhos'),
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('Equipe before the roles are read waits in the detail, '
        'never blank', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: (_) => staffFirstItem(null))),
      );

      expect(find.byType(FamilyPlaceholder), findsOneWidget);
      expect(find.bySemanticsLabel('Carregando a equipe'), findsOneWidget);
    });
  });
}

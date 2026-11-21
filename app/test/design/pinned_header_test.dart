import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/pinned_header.dart';

const edge = Color(0xFF00FF00);
const header = Key('header');
const lead = Key('lead');

/// A [height] header over a long column in a 360 × 640 viewport.
Future<void> pumpHeader(WidgetTester tester, double height) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: CustomScrollView(
        slivers: [
          PinnedHeader(
            edge: edge,
            // Its own ground, which takes the touches over what is beneath.
            child: ColoredBox(
              key: header,
              color: const Color(0xFFFFFFFF),
              child: SizedBox(height: height),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 48, child: Text('linha $i')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// A [leadHeight] lead over a [height] header over a long column in a
/// 360 × 640 viewport.
Future<void> pumpLed(
  WidgetTester tester, {
  required double leadHeight,
  required double height,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: CustomScrollView(
        slivers: [
          PinnedHeader(
            edge: edge,
            lead: ColoredBox(
              key: lead,
              color: const Color(0xFFFFFFFF),
              child: SizedBox(height: leadHeight),
            ),
            child: ColoredBox(
              key: header,
              color: const Color(0xFFFFFFFF),
              child: SizedBox(height: height),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 48, child: Text('linha $i')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

double topOf(WidgetTester tester, Key key) =>
    tester.getTopLeft(find.byKey(key)).dy;

Future<void> scrollBy(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(CustomScrollView), Offset(0, -dy));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a header that leaves at least half the height stays at the '
      'top while the content scrolls beneath it', (tester) async {
    await pumpHeader(tester, 320);

    await scrollBy(tester, 400);

    expect(tester.getTopLeft(find.byKey(header)).dy, 0);
    expect(
      tester
          .hitTestOnBinding(const Offset(10, 300))
          .path
          .any((e) => e.target == tester.renderObject(find.byKey(header))),
      isTrue,
      reason: 'the header takes the touches over the content beneath',
    );
  });

  testWidgets('its lower edge is drawn only while content is under it', (
    tester,
  ) async {
    await pumpHeader(tester, 200);
    final sliver = find.byType(PinnedHeader);

    expect(sliver, paintsExactlyCountTimes(#drawRect, 1));
    await scrollBy(tester, 100);
    expect(
      sliver,
      paints
        ..rect(color: const Color(0xFFFFFFFF))
        ..rect(rect: const Rect.fromLTWH(0, 199, 360, 1), color: edge),
    );
    await scrollBy(tester, -100);
    expect(sliver, paintsExactlyCountTimes(#drawRect, 1));
  });

  testWidgets('a header that would leave less than half the height scrolls '
      'with the content, with no edge drawn', (tester) async {
    await pumpHeader(tester, 321);

    await scrollBy(tester, 100);

    expect(tester.getTopLeft(find.byKey(header)).dy, -100);
    expect(find.byType(PinnedHeader), paintsExactlyCountTimes(#drawRect, 1));
  });

  testWidgets('a widget revealed below it is not left beneath it', (
    tester,
  ) async {
    await pumpHeader(tester, 200);

    await tester.ensureVisible(find.text('linha 30'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('linha 2'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('linha 2')).dy,
      greaterThanOrEqualTo(200),
    );
  });

  group('with a lead', () {
    testWidgets('both stay at the top when together they leave at least half '
        'the height', (tester) async {
      await pumpLed(tester, leadHeight: 100, height: 220);

      await scrollBy(tester, 400);

      expect(topOf(tester, lead), 0);
      expect(topOf(tester, header), 100);
      expect(
        find.byType(PinnedHeader),
        paints
          ..rect()
          ..rect()
          ..rect(rect: const Rect.fromLTWH(0, 319, 360, 1), color: edge),
      );
    });

    testWidgets('otherwise the lead scrolls away and the header stays, when '
        'it alone leaves at least half the height', (tester) async {
      await pumpLed(tester, leadHeight: 100, height: 260);

      await scrollBy(tester, 60);
      expect(topOf(tester, lead), -60);
      expect(topOf(tester, header), 40);
      expect(
        find.byType(PinnedHeader),
        paintsExactlyCountTimes(#drawRect, 2),
        reason: 'no edge until content is under the header',
      );

      await scrollBy(tester, 340);
      expect(topOf(tester, header), 0);
      expect(
        find.byType(PinnedHeader),
        paints
          ..rect(rect: const Rect.fromLTWH(0, 0, 360, 260))
          ..rect(rect: const Rect.fromLTWH(0, 259, 360, 1), color: edge),
      );
      expect(
        tester
            .hitTestOnBinding(const Offset(10, 200))
            .path
            .any((e) => e.target == tester.renderObject(find.byKey(header))),
        isTrue,
        reason: 'the header takes the touches over the content beneath',
      );
      await tester.ensureVisible(find.text('linha 30'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('linha 12'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('linha 12')).dy,
        greaterThanOrEqualTo(260),
        reason: 'a widget revealed is not left beneath the header',
      );
    });

    testWidgets('neither stays when the header alone would leave less than '
        'half the height', (tester) async {
      await pumpLed(tester, leadHeight: 100, height: 321);

      await scrollBy(tester, 200);

      expect(topOf(tester, lead), -200);
      expect(topOf(tester, header), -100);
      // The lead, scrolled out of view, is not painted: only the header.
      expect(find.byType(PinnedHeader), paintsExactlyCountTimes(#drawRect, 1));
    });
  });
}

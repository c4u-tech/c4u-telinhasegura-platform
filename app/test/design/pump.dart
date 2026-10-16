import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/address.dart';
import 'package:telinha_segura/design/theme.dart';
import 'package:telinha_segura/design/tokens.dart';

/// The grounds a shared component sits on: the guardian's cream world in
/// either theme, or the kid dialect's ink.
enum Ground { light, dark, kid }

ThemeData themeOf(Ground ground) => switch (ground) {
  Ground.light => buildTheme(Brightness.light),
  Ground.dark => buildTheme(Brightness.dark),
  Ground.kid => buildTheme(Brightness.dark, Palette.kid),
};

/// Pumps [child] in a column on [ground] at [size] and [textScale].
Future<void> pumpOn(
  WidgetTester tester,
  Widget child, {
  Ground ground = Ground.light,
  Size size = const Size(360, 640),
  double textScale = 1,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: themeOf(ground),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
}

/// Every label, value, hint and tooltip in the semantics tree.
List<String> semanticsStrings(WidgetTester tester) => [
  for (final node in find.semantics.byPredicate((_) => true).evaluate())
    for (final text in [node.label, node.value, node.hint, node.tooltip])
      if (text.isNotEmpty) text,
];

/// The lines [paragraph] laid its text out on, as plain text: without the
/// zero-width break opportunities and word joiners an address carries.
List<String> linesOf(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  // The same text, laid out again at the paragraph's width and scale.
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: paragraph.maxLines,
  )..layout(maxWidth: paragraph.constraints.maxWidth);
  addTearDown(painter.dispose);
  final lines = <String>[];
  var offset = 0;
  while (offset < text.length) {
    final line = painter.getLineBoundary(TextPosition(offset: offset));
    if (line.end <= offset) break;
    lines.add(text.substring(line.start, line.end));
    offset = line.end;
  }
  return [for (final l in lines) l.replaceAll(RegExp('[​⁠]'), '')];
}

/// Fails unless every line break in [lines] falls after an "@" or before
/// a ".", the only places an address may break.
void expectAddressBreaks(List<String> lines) {
  for (var i = 0; i < lines.length - 1; i++) {
    expect(
      lines[i].endsWith('@') || lines[i + 1].startsWith('.'),
      isTrue,
      reason: 'broke between "${lines[i]}" and "${lines[i + 1]}"',
    );
  }
}

/// Finds [address] set by the Plain Address Rule: shown with its break
/// marks ([addressBreaks]), so a plain `find.text(address)` misses it.
Finder findAddress(String address) => find.text(addressBreaks(address));

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/address.dart';

import 'pump.dart';

void main() {
  test('an address may break only after "@" and before "."', () {
    expect(addressBreaks('ana.souza@example.com'), 'ana​.souza@​example​.com');
  });

  test('a hyphen holds its neighbours together, as "e-mail" does', () {
    expect(addressBreaks('ana-maria@x.com'), 'ana-⁠maria@​x​.com');
  });

  testWidgets('a long address wraps at its safe points only', (tester) async {
    // The test font sets every glyph about one em wide: 10 glyphs of
    // 16 px fit the 160 px box.
    await pumpOn(
      tester,
      const SizedBox(
        width: 160,
        child: AddressText(
          'ana.souza.oliveira@example.com.br',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    final lines = linesOf(paragraph);
    expect(lines.length, greaterThan(1));
    expect(lines.join(), 'ana.souza.oliveira@example.com.br');
    expectAddressBreaks(lines);
  });

  testWidgets('assistive technology reads the plain address', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpOn(tester, const AddressText('ana.souza@example.com'));

    expect(find.bySemanticsLabel('ana.souza@example.com'), findsOneWidget);
    expect(semanticsStrings(tester).where((s) => s.contains('​')), isEmpty);
    semantics.dispose();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';
import 'package:telinha_segura/kid_mode/link_qr.dart';

void main() {
  test('the link carries the code as the server returned it', () {
    expect(linkUri('ABCD-1234'), 'telinhasegura://vincular?codigo=ABCD-1234');
  });

  test('the code reads as two groups of four, and character by character', () {
    expect(codeGroups('ABCD-1234'), ('ABCD', '1234'));
    expect(codeGroups('abcd1234'), ('abcd', '1234'));
    expect(spokenCode('ABCD-1234'), 'A, B, C, D, 1, 2, 3, 4');
  });

  testWidgets('the QR encodes the link, square modules in a 4-module quiet '
      'zone, labelled with the same code', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: LinkQr(code: 'ABCD-1234')),
        ),
      ),
    );

    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(LinkQr),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as LinkQrPainter;
    final expected = QrImage(
      QrCode(
        payload: QrPayload.fromString(
          'telinhasegura://vincular?codigo=ABCD-1234',
        ),
      ),
    );
    expect(painter.data, 'telinhasegura://vincular?codigo=ABCD-1234');
    expect(painter.image.moduleCount, expected.moduleCount);
    for (var r = 0; r < expected.moduleCount; r++) {
      for (var c = 0; c < expected.moduleCount; c++) {
        expect(painter.image.isDark(r, c), expected.isDark(r, c));
      }
    }
    expect(LinkQrPainter.quietZone, 4);

    // Whole pixels per module: the modules stay crisp squares.
    final size = tester.getSize(find.byType(LinkQr));
    final module = LinkQrPainter.moduleSize(
      size.shortestSide,
      expected.moduleCount,
    );
    expect(module, module.roundToDouble());
    expect(module, greaterThanOrEqualTo(4));

    expect(
      tester.getSemantics(find.byType(LinkQr)),
      matchesSemantics(
        label: 'QR com o código A, B, C, D, 1, 2, 3, 4',
        isImage: true,
      ),
    );
    semantics.dispose();
  });
}

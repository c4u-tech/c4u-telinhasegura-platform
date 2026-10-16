import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../design/tokens.dart';

/// The link the child's camera opens in the app: the code exactly as the
/// server returned it (the redemption screen reads it).
String linkUri(String code) => 'telinhasegura://vincular?codigo=$code';

/// The code's characters as two groups of four, separators dropped.
(String, String) codeGroups(String code) {
  final chars = code.replaceAll(RegExp(r'[\s-]'), '');
  final half = (chars.length / 2).ceil();
  return (chars.substring(0, half), chars.substring(half));
}

/// The code for assistive technology, one character at a time.
String spokenCode(String code) {
  final (a, b) = codeGroups(code);
  return '$a$b'.split('').join(', ');
}

/// The link code as a QR, drawn here from the pure-Dart `qr` encoder (no
/// plugin, no camera): ink modules on the paper-input ground in both
/// themes, so any camera reads it, labelled with the code it holds.
class LinkQr extends StatelessWidget {
  const LinkQr({super.key, required this.code, this.size = 216});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'QR com o código ${spokenCode(code)}',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * Radii.screenRatio / 4),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: LinkQrPainter(linkUri(code))),
      ),
    ),
  );
}

class LinkQrPainter extends CustomPainter {
  LinkQrPainter(this.data)
    : image = QrImage(QrCode(payload: QrPayload.fromString(data)));

  final String data;
  final QrImage image;

  /// The light margin a reader needs, in modules.
  static const quietZone = 4;

  /// Whole logical pixels per module, so every module is a crisp square.
  static double moduleSize(double side, int modules) =>
      (side / (modules + 2 * quietZone)).floorToDouble();

  static final _ground = Paint()..color = Palette.light.input;
  static final _module = Paint()
    ..color = BrandColors.ink
    ..isAntiAlias = false;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _ground);
    final n = image.moduleCount;
    final m = moduleSize(size.shortestSide, n);
    // Centred on whole pixels; what the floor left over joins the margin.
    final origin = Offset(
      ((size.width - n * m) / 2).floorToDouble(),
      ((size.height - n * m) / 2).floorToDouble(),
    );
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (!image.isDark(r, c)) continue;
        canvas.drawRect(origin + Offset(c * m, r * m) & Size(m, m), _module);
      }
    }
  }

  @override
  bool shouldRepaint(LinkQrPainter old) => old.data != data;
}

import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import '../kid_mode/link_qr.dart' show LinkQrPainter;

/// [text]'s groups as assistive technology reads them: each group's
/// characters one by one, the groups apart ("A B C D, E F G H").
String spokenGroups(Iterable<String> groups) =>
    groups.map((g) => g.split('').join(' ')).join(', ');

/// The secret in blocks of four, as the key block shows it.
List<String> keyGroups(String secret) {
  final chars = secret.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  return [
    for (var i = 0; i < chars.length; i += 4)
      chars.substring(i, (i + 4).clamp(0, chars.length)),
  ];
}

/// The key and code style: Bricolage title-medium with tabular figures
/// and open tracking (MFA amendment, World).
TextStyle? codeStyle(BuildContext context) {
  final style = Theme.of(context).textTheme.titleMedium;
  return style?.copyWith(
    letterSpacing: 0.08 * (style.fontSize ?? 18),
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// The key block: one-time secrets on the paper-input ground with the
/// control radius and the outline stroke, selectable (the key, the
/// recovery codes).
class CodeBlock extends StatelessWidget {
  const CodeBlock({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.input,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: p.outline, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.lg,
        ),
        child: SelectionArea(child: child),
      ),
    );
  }
}

/// What the key's QR says to assistive technology.
const keyQrLabel = 'QR code da chave; a mesma chave está em texto abaixo';

/// The `otpauth://` link as a QR, exactly as the server sent it:
/// ink on paper inside its quiet zone, never under a
/// scannable 200 dp, outlined as the key block is.
class KeyQr extends StatelessWidget {
  const KeyQr({super.key, required this.uri, this.size = 216});

  final String uri;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * Radii.screenRatio / 4);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        image: true,
        label: keyQrLabel,
        // The stroke is drawn over the quiet zone's edge, never the code.
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: context.palette.outline, width: 1.5),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: SizedBox.square(
              dimension: size,
              child: CustomPaint(painter: LinkQrPainter(uri)),
            ),
          ),
        ),
      ),
    );
  }
}

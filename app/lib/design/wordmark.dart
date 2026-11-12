import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The brand's wordmark alone, in cream, for the ink field the head
/// already peeks over: field, head and letters together make the mark, so
/// the field does not repeat the mark beside its letters. It is the
/// field's name plate, set under the head at a size from WordmarkSizes.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, required this.height});

  static const asset = 'assets/brand/telinha-segura-wordmark-reversed.svg';

  /// The wordmark's box, from the top of its ascenders to the foot of its
  /// descenders.
  final double height;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset(asset, height: height, semanticsLabel: 'Telinha Segura');
}

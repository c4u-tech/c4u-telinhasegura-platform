import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The brand's wordmark alone, for the ink field the mascot already
/// stands on: cream letters with the coral play mark as the dot of the
/// i, the one touch of the beak's colour outside the figure. Field,
/// figure and letters together make the mark, so the field does not
/// repeat the figure beside its letters. It is the field's name plate,
/// set below the mascot at a size from WordmarkSizes.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, required this.height});

  static const asset = 'assets/brand/telinha-segura-wordmark-color-on-dark.svg';

  /// The wordmark's box, from the top of its ascenders to the foot of its
  /// descenders.
  final double height;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset(asset, height: height, semanticsLabel: 'Telinha Segura');
}

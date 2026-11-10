import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The brand's wordmark alone, in cream, for the ink field the head
/// already peeks over: field, head and letters together make the mark, so
/// the field does not repeat the mark beside its letters.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, required this.lockupHeight});

  static const asset = 'assets/brand/telinha-segura-wordmark-reversed.svg';

  /// The lockup height whose letters this matches: the wordmark file is
  /// 29 of the lockup's 64 units tall, with letters of the same size.
  final double lockupHeight;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    asset,
    height: lockupHeight * 29 / 64,
    semanticsLabel: 'Telinha Segura',
  );
}

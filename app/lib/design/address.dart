import 'package:flutter/widgets.dart';

/// [address] prepared for a narrow line: a zero-width break opportunity
/// after the "@" and before every ".", and a word joiner after each
/// hyphen (the Whole Word Rule's "e-⁠mail"), so a line breaks it only
/// where it still reads as an address. Bricolage has no non-breaking
/// hyphen, hence the joiner.
///
/// For display only: what is read aloud, compared or sent stays [address].
String addressBreaks(String address) => address.replaceAllMapped(
  RegExp('[@.-]'),
  (m) => switch (m[0]) {
    '@' => '@​',
    '.' => '​.',
    _ => '-⁠',
  },
);

/// An email address set with [addressBreaks], read to assistive
/// technology as the plain [address].
class AddressText extends StatelessWidget {
  const AddressText(this.address, {super.key, this.style});

  final String address;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) =>
      Text(addressBreaks(address), style: style, semanticsLabel: address);
}

import 'family.dart';

/// PT-BR words for the family model, in the same voice as the access copy
/// (lib/access/copy.dart).
extension AgeBandLabel on AgeBand {
  String get label => switch (this) {
    AgeBand.upTo4 => '2 a 4 anos',
    AgeBand.from5To8 => '5 a 8 anos',
    AgeBand.from9To12 => '9 a 12 anos',
    AgeBand.unknown => 'Faixa não informada',
  };
}

/// The animal's name: each avatar's label for assistive technology.
extension AvatarLabel on Avatar {
  String get label => switch (this) {
    Avatar.fox => 'raposa',
    Avatar.owl => 'coruja',
    Avatar.cat => 'gato',
    Avatar.dog => 'cachorro',
    Avatar.rabbit => 'coelho',
    Avatar.bear => 'urso',
    Avatar.turtle => 'tartaruga',
    Avatar.whale => 'baleia',
    Avatar.lion => 'leão',
    Avatar.panda => 'panda',
    Avatar.frog => 'sapo',
    Avatar.penguin => 'pinguim',
    Avatar.unknown => 'avatar não informado',
  };
}

/// The counts beside the capacity modules; they always state the same
/// number the modules show.
abstract final class FamilyWords {
  static String children(int n) => '$n de $kMaxMinors crianças';

  /// The adults' places: [members] take one each, and so does each
  /// pending invitation. When some wait, the words name both kinds:
  /// "4 de 6 vagas: 3 adultos e 1 convite".
  static String adults(int members, int invitations) {
    final places = '${members + invitations} de $kMaxAdults vagas';
    if (invitations == 0) return places;
    final adults = members == 1 ? '1 adulto' : '$members adultos';
    final waiting = invitations == 1 ? '1 convite' : '$invitations convites';
    return '$places: $adults e $waiting';
  }

  /// The bounded set before a family exists, all of it free.
  static const childrenRoom = 'Cabem até $kMaxMinors crianças';
  static const adultsRoom = 'e até $kMaxAdults adultos';

  static String invitationsWaiting(int n) => switch (n) {
    0 => 'Nenhum convite esperando resposta',
    1 => '1 convite esperando resposta',
    _ => '$n convites esperando resposta',
  };

  /// When a pending invitation expires, in calendar days on the device's
  /// clock: "expira hoje", "expira amanhã", "expira em 5 dias". A time
  /// already past still reads "hoje": the server says what is pending.
  static String expiry(DateTime expiresAt, DateTime now) {
    final local = expiresAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    // Rounded: a daylight-saving day is 23 or 25 hours long.
    final days = (day.difference(today).inHours / 24).round();
    return switch (days) {
      <= 0 => 'expira hoje',
      1 => 'expira amanhã',
      _ => 'expira em $days dias',
    };
  }

  /// [names] as a PT-BR list: "Lia", "Lia e Téo", "Lia, Téo e Nina".
  static String names(List<String> names) => names.length < 2
      ? names.join()
      : '${names.sublist(0, names.length - 1).join(', ')} e ${names.last}';
}

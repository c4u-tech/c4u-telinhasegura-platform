import '../parental/parental.dart';
import '../parental/parental_api.dart';

/// The most devices a family links.
const kMaxDevices = 10;

/// What the "Modo criança" door and `/modo-crianca` show: whether the
/// family has a PIN, and its linked devices.
class KidModeStatus {
  const KidModeStatus({required this.pinSet, required this.devices});

  final bool pinSet;
  final List<LinkedDevice> devices;

  /// Both reads at once; the first failure is the one thrown.
  static Future<KidModeStatus> read(ParentalApi api) async {
    final both = await Future.wait<Object>([api.pinIsSet(), api.devices()]);
    return KidModeStatus(
      pinSet: both[0] as bool,
      devices: both[1] as List<LinkedDevice>,
    );
  }
}

/// Said in place of the door's state when either read failed.
const kidModeUnknown = 'Não conseguimos ver o PIN e os aparelhos agora.';

/// The kid-mode words beside the state modules; they always state what
/// the modules show.
abstract final class KidModeWords {
  static String pin(bool set) => set ? 'PIN criado' : 'Crie o PIN para começar';

  static String devices(int n) => switch (n) {
    0 => 'Nenhum aparelho vinculado',
    1 => '1 aparelho vinculado',
    _ => '$n aparelhos vinculados',
  };

  /// The capacity row's words: "2 de 10 aparelhos".
  static String capacity(int n) => '$n de $kMaxDevices aparelhos';

  /// A link code's time [left] in whole minutes, rounded down so it never
  /// promises more than there is.
  static String expiresIn(Duration left) => left.inMinutes < 1
      ? 'expira em menos de 1\u00A0min'
      : 'expira em ${left.inMinutes}\u00A0min';

  /// When a device was last used, in calendar days on the device clock.
  /// A time ahead of [now] still reads "hoje".
  static String lastUsed(DateTime seenAt, DateTime now) {
    final local = seenAt.toLocal();
    final here = now.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(here.year, here.month, here.day);
    // Rounded: a daylight-saving day is 23 or 25 hours long.
    final days = (today.difference(day).inHours / 24).round();
    return switch (days) {
      <= 0 => 'usado hoje',
      1 => 'usado ontem',
      _ => 'usado há $days dias',
    };
  }
}

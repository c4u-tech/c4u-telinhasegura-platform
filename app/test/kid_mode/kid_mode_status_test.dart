import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/kid_mode/kid_mode_status.dart';

void main() {
  test('a link code expires in whole minutes, never overstated, and says '
      'when less than one is left', () {
    String words(int seconds) =>
        KidModeWords.expiresIn(Duration(seconds: seconds));
    expect(words(600), 'expira em 10\u00A0min');
    expect(words(599), 'expira em 9\u00A0min');
    expect(words(120), 'expira em 2\u00A0min');
    expect(words(60), 'expira em 1\u00A0min');
    expect(words(59), 'expira em menos de 1\u00A0min');
    expect(words(1), 'expira em menos de 1\u00A0min');
  });

  test('a device was last used today, yesterday or some days ago, in '
      'calendar days on the device clock', () {
    final now = DateTime(2026, 10, 3, 9);
    String words(DateTime seen) => KidModeWords.lastUsed(seen, now);
    expect(words(DateTime(2026, 10, 3, 0, 5)), 'usado hoje');
    expect(words(DateTime(2026, 10, 2, 23, 50)), 'usado ontem');
    expect(words(DateTime(2026, 10, 1, 12)), 'usado há 2 dias');
    expect(words(DateTime(2026, 9, 3, 12)), 'usado há 30 dias');
    // A clock behind the server's still reads "hoje".
    expect(words(DateTime(2026, 10, 4, 12)), 'usado hoje');
  });
}

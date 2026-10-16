import 'dart:async';

import 'package:flutter/material.dart';

import '../access/widgets.dart';
import '../account/sessions_screen.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';

/// The way out of a block a stolen session may be keeping up.
const sessionsDoor = 'Não foi você? Encerre a sessão nos outros aparelhos.';

/// The blocked factor's note, in whole minutes; the
/// number and "min" never part across a line.
String blockedFor(int minutes) =>
    'Muitas tentativas erradas. Tente de novo em $minutes\u00A0min.';

/// A factor blocked by `rate_limited`, the
/// challenge's and the enrollment's code step's alike: counted by the
/// second from `Retry-After`, but notifying, and so announced, only as the
/// whole minutes change, and once more as it ends.
class FactorBlock extends ChangeNotifier {
  int? _left;
  Timer? _timer;

  /// Whether the field and its primary wait.
  bool get active => _left != null;

  /// The minutes left, rounded up; null when not blocked.
  int? get minutes => switch (_left) {
    final left? => _minutesOf(left),
    null => null,
  };

  static int _minutesOf(int seconds) => (seconds / 60).ceil();

  void start(Duration wait) {
    _timer?.cancel();
    _left = wait.inSeconds.clamp(1, 24 * 60 * 60);
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final before = _minutesOf(_left!);
      final left = _left! - 1;
      if (left <= 0) {
        t.cancel();
        _left = null;
        notifyListeners();
      } else {
        _left = left;
        if (_minutesOf(left) != before) notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The blocked state under a factor's field: the clay note, a live region
/// whose words change once a minute, then the door to the sessions,
/// pushed over the screen so coming back finds it as it was.
class BlockedNote extends StatelessWidget {
  const BlockedNote({super.key, required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ErrorNote(blockedFor(minutes)),
      const SizedBox(height: Space.sm),
      Doors(
        children: [
          DoorRow(
            title: sessionsDoor,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (route) =>
                    SessionsScreen(onBack: () => Navigator.of(route).pop()),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

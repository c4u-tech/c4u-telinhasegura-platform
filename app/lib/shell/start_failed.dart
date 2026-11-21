import 'package:flutter/material.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../kid/kid_layout.dart';
import '../kid/shelves.dart';

/// What the app shows when, at its start, it could not learn who it is in
/// front of: the server did not answer. A guardian's task screen (the band
/// with the mascot and the wordmark, a title, the note and "Tentar de
/// novo"), with no way back, there being nowhere to go back to. On a
/// device that may be in a child's hands it stays in the child's world:
/// the failed shelf on the child's ground, with no adult band.
///
/// [onRetry] reads again; while [busy] the retry waits. A try that fails
/// again leaves the same screen, its note said anew, never a second one.
class StartFailed extends StatelessWidget {
  const StartFailed({
    super.key,
    required this.onRetry,
    this.busy = false,
    this.child = false,
    this.attempt = 0,
  });

  final VoidCallback onRetry;
  final bool busy;

  /// Whether a child may hold the device.
  final bool child;

  /// How many tries failed so far: a new failure renews the note, so it is
  /// announced again in place of the last.
  final int attempt;

  static const title = 'Sem conexão agora';

  @override
  Widget build(BuildContext context) {
    if (child) {
      final wide =
          MediaQuery.sizeOf(context).width >= FieldSizes.wideBreakpoint;
      return KidLayout(
        // The picture's mascot is the screen's one.
        mark: false,
        child: ShelvesFailed(
          onRetry: onRetry,
          busy: busy,
          scale: wide ? 1.5 : 1.25,
        ),
      );
    }
    return FieldLayout(
      title: title,
      children: [
        ErrorNote(Copy.genericRetry, key: ValueKey(attempt)),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', busy: busy, onPressed: onRetry),
      ],
    );
  }
}

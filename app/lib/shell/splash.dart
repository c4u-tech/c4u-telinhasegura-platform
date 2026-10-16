import 'package:flutter/material.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// Shown while the app does not yet know who it is in front of:
/// the plain ground, nothing to read
/// or press. Only a failed read of the mode says so and offers
/// "Tentar de novo", which calls [onRetry].
class Splash extends StatelessWidget {
  const Splash({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ground = context.palette.ground;
    final retry = onRetry;
    if (retry == null) {
      return Semantics(
        label: 'Carregando',
        child: ColoredBox(color: ground),
      );
    }
    return Material(
      color: ground,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ErrorNote(Copy.genericRetry),
                  const SizedBox(height: Space.lg),
                  PrimaryButton(label: 'Tentar de novo', onPressed: retry),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

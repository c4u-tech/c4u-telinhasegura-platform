import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/provider_sign_in.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'provider_flow.dart';
import 'submission.dart';
import 'widgets.dart';

/// `/entrar`: the promise on the field, then every way in, and on
/// a phone or tablet the way to link it to a child.
class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _submission = Submission();
  StreamSubscription<String>? _googleTokens;
  bool _started = false;

  /// Why the app was signed out, taken once from the services.
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      final services = AppScope.of(context);
      _notice = services.entryNotice;
      services.entryNotice = null;
    }
    // The web's Google button delivers tokens on a stream this screen
    // holds for exactly its lifetime.
    _googleTokens ??= AppScope.of(context).googleWeb?.idTokens().listen((
      token,
    ) {
      if (!mounted) return;
      offerProviderToken(context, _submission, IdentityProvider.google, token);
    });
  }

  @override
  void dispose() {
    _googleTokens?.cancel();
    _submission.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: _submission,
      builder: (context, _) {
        final idle = !_submission.blocked;
        return FieldLayout(
          size: FieldSize.hero,
          title: 'Entrar',
          children: [
            if (_notice case final notice?) ...[
              Notice(notice),
              const SizedBox(height: Space.xl),
            ],
            if (offersProviders(services)) ...[
              ProviderChoices(
                onPressed: idle
                    ? (p) => signInWithProvider(context, _submission, p)
                    : null,
              ),
              const OrDivider(),
            ],
            FilledButton(
              onPressed: idle ? () => context.go(Routes.emailSignIn) : null,
              child: const Text('Entrar com e-\u2060mail'),
            ),
            if (_submission.message case final message?) ...[
              const SizedBox(height: Space.lg),
              ErrorNote(message),
            ],
            const SizedBox(height: Space.xxl),
            SignupInvite(onPressed: () => context.go(Routes.signup)),
            // A child's own Android or iOS device is linked, never signed
            // in. A stored credential never shows this
            // screen at all: the mode gate keeps it on /crianca.
            if (services.child.canLink)
              Center(
                child: TextButton(
                  onPressed: idle ? () => context.go(Routes.redeem) : null,
                  child: const Text('Este aparelho é de uma criança'),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "Primeira vez aqui? Criar conta", shared by the sign-in screens.
class SignupInvite extends StatelessWidget {
  const SignupInvite({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        'Primeira vez aqui?',
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: context.palette.muted),
      ),
      TextButton(onPressed: onPressed, child: const Text('Criar conta')),
    ],
  );
}

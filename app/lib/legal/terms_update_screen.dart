import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../family/family_model.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'legal_links.dart';

const termsUpdateText =
    'Atualizamos os Termos de uso e a Política de privacidade. Leia e, se '
    'estiver de acordo, toque em Concordo.';

/// `/termos`: an account that has not accepted the current terms and
/// privacy policy waits here, from any of its routes, until it agrees or
/// signs out. There is no way back: everything else waits on the answer.
class TermsUpdateScreen extends StatefulWidget {
  const TermsUpdateScreen({super.key});

  @override
  State<TermsUpdateScreen> createState() => _TermsUpdateScreenState();
}

class _TermsUpdateScreenState extends State<TermsUpdateScreen> {
  final _accept = Submission();
  final _signOut = Submission();
  late final FamilyModel _model;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    // Arriving here directly reads the session, which decides whether the
    // screen is still owed. It notifies the router, so after this build.
    scheduleMicrotask(_model.load);
  }

  @override
  void dispose() {
    _accept.dispose();
    _signOut.dispose();
    super.dispose();
  }

  Future<void> _agree() async {
    final ok = await _accept.run(() => AppScope.of(context).auth.acceptTerms());
    if (!ok) return;
    await _model.termsAcceptedNow();
    if (mounted) context.go(Routes.home);
  }

  /// `signOut` forgets the local session even when the server cannot be
  /// reached, and the router then leaves this screen.
  Future<void> _leave() =>
      _signOut.run(() => AppScope.of(context).auth.signOut());

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_accept, _signOut]),
    builder: (context, _) => FieldLayout(
      title: 'Atualizamos os termos',
      children: [
        Text(termsUpdateText, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: Space.md),
        const LegalLinks(),
        const SizedBox(height: Space.xl),
        if (_accept.message ?? _signOut.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.lg),
        ],
        PrimaryButton(
          label: 'Concordo',
          busy: _accept.busy,
          onPressed: _accept.blocked || _signOut.busy ? null : _agree,
        ),
        const SizedBox(height: Space.xl),
        QuietAction(
          label: 'Sair da conta',
          busy: _signOut.busy,
          onPressed: _accept.busy ? null : _leave,
        ),
      ],
    ),
  );
}

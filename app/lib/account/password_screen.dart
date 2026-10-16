import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/forgot_password_screen.dart' show resetLinkSent;
import '../access/new_password.dart';
import '../access/reauth_prompt.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family_model.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'account_write.dart';

/// What a password change did: the server ended the other sessions and
/// mailed a confirmation.
const passwordChanged =
    'Senha trocada. Saímos da sua conta nos outros aparelhos e enviamos um '
    'e-⁠mail confirmando a troca.';

/// The lead-in of "Criar uma senha": the app cannot tell whether the
/// account has a password, so both paths show.
const createLeadIn =
    'Entrou com Google ou Apple? Receba um link para criar uma senha.';

/// `/conta/senha`: change the password
/// or, for an account made with Google or Apple, ask for the recovery's
/// link to create one. The passwords live only in their fields
/// and go after every call, success or failure.
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _create = Submission();
  late final AccountWrite _change;
  late final FamilyModel _model;
  bool _started = false;
  bool _changed = false;
  bool _linkSent = false;
  String? _currentError;
  String? _nextError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    _model = services.familyModel;
    // The account's email, where the link goes, comes with the family's
    // first read.
    scheduleMicrotask(_model.load);
    _change = AccountWrite(
      confirm: () => confirmItsYou(context),
      signOut: services.client.forgetSession,
    );
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _change.dispose();
    _create.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!longEnough(_next.text)) {
      setState(() => _nextError = tooShortMessage);
      return;
    }
    final auth = AppScope.of(context).auth;
    final current = _current.text;
    final next = _next.text;
    setState(() {
      _currentError = null;
      _nextError = null;
    });
    final ok = await _change.write(
      () => auth.changePassword(current: current, next: next),
      handle: (e) {
        if (e.code == 'invalid_credentials') {
          setState(() => _currentError = Copy.currentPasswordWrong);
          return true;
        }
        final onField = passwordFieldError(e);
        if (onField != null) setState(() => _nextError = onField);
        return onField != null;
      },
    );
    if (!mounted) return;
    // A password manager may save the new one before the fields go.
    if (ok) TextInput.finishAutofillContext();
    _current.clear();
    _next.clear();
    setState(() => _changed = ok);
  }

  /// The recovery's link, to the account's own address; its answer never
  /// says whether the account had a password.
  Future<void> _sendLink(String email) async {
    final auth = AppScope.of(context).auth;
    final ok = await _create.run(() => auth.requestPasswordReset(email));
    if (ok && mounted) setState(() => _linkSent = true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_change, _create, _model]),
    builder: (context, _) => FieldLayout(
      title: _linkSent ? 'Criar uma senha' : 'Trocar a senha',
      onBack: () => context.go(Routes.account),
      children: switch ((_linkSent, _changed)) {
        (true, _) => _done(resetLinkSent),
        (_, true) => _done(passwordChanged),
        _ => _form(),
      },
    ),
  );

  /// A finished errand: what happened, and the way back.
  List<Widget> _done(String notice) => [
    Notice(notice),
    const SizedBox(height: Space.xl),
    FilledButton(
      onPressed: () => context.go(Routes.account),
      child: const Text('Voltar para sua conta'),
    ),
  ];

  List<Widget> _form() {
    final email = _model.email;
    return [
      AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(
              controller: _current,
              label: 'Senha atual',
              errorText: _currentError,
              onChanged: (_) => setState(() => _currentError = null),
            ),
            const SizedBox(height: Space.lg),
            NewPasswordField(
              controller: _next,
              label: 'Nova senha',
              errorText: _nextError,
              onChanged: (_) => setState(() => _nextError = null),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.xl),
      if (_change.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Trocar senha',
        busy: _change.busy,
        onPressed: _change.blocked ? null : _submit,
      ),
      const SizedBox(height: Space.xxl),
      Text(
        createLeadIn,
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: context.palette.muted),
      ),
      const SizedBox(height: Space.xs),
      if (_create.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.xs),
      ],
      QuietAction(
        label: 'Criar uma senha',
        busy: _create.busy,
        onPressed: email == null || _create.blocked
            ? null
            : () => _sendLink(email),
      ),
    ];
  }
}

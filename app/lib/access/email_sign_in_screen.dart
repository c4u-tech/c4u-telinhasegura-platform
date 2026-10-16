import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'entry_screen.dart';
import 'submission.dart';
import 'widgets.dart';

/// `/entrar/email`.
class EmailSignInScreen extends StatefulWidget {
  const EmailSignInScreen({super.key});

  @override
  State<EmailSignInScreen> createState() => _EmailSignInScreenState();
}

class _EmailSignInScreenState extends State<EmailSignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _submission = Submission();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _submission.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final services = AppScope.of(context);
    final ok = await _submission.run(
      () async => services.auth.signIn(
        email: _email.text.trim(),
        password: _password.text,
        deviceLabel: await services.deviceLabel.read(),
      ),
      handle: (e) {
        // Never say which field was wrong; the password goes.
        if (e.code == 'invalid_credentials') _password.clear();
        return false;
      },
    );
    if (ok) TextInput.finishAutofillContext();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _submission,
    builder: (context, _) => FieldLayout(
      title: 'Entrar com e-\u2060mail',
      onBack: () => context.go(Routes.entry),
      children: [
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EmailField(controller: _email, autofocus: true),
              const SizedBox(height: Space.lg),
              PasswordField(
                controller: _password,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.go(Routes.forgotPassword),
            child: const Text('Esqueci a senha'),
          ),
        ),
        const SizedBox(height: Space.sm),
        if (_submission.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.lg),
        ],
        PrimaryButton(
          label: 'Entrar',
          busy: _submission.busy,
          onPressed: _submission.blocked ? null : _submit,
        ),
        const SizedBox(height: Space.xxl),
        SignupInvite(onPressed: () => context.go(Routes.signup)),
      ],
    ),
  );
}

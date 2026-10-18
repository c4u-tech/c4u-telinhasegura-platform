import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../legal/legal_links.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'new_password.dart';
import 'submission.dart';
import 'widgets.dart';

/// The adult declaration.
const adultDeclaration = 'Declaro que tenho 18 anos ou mais.';

/// `/criar-conta`, step 1 of 2.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _submission = Submission();
  bool _adult = false;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _submission.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!longEnough(_password.text)) {
      setState(() => _passwordError = tooShortMessage);
      return;
    }
    final email = _email.text.trim();
    final ok = await _submission.run(
      () => AppScope.of(context).auth.signUp(
        email: email,
        password: _password.text,
        adultDeclaration: _adult,
      ),
      handle: (e) {
        final onField = passwordFieldError(e);
        if (onField != null) setState(() => _passwordError = onField);
        return onField != null;
      },
    );
    if (!ok || !mounted) return;
    TextInput.finishAutofillContext();
    context.go(Routes.checkEmail, extra: email);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _submission,
    builder: (context, _) => FieldLayout(
      title: 'Criar conta',
      onBack: () => context.go(Routes.entry),
      children: [
        const StepMarks(step: 1, of: 2),
        const SizedBox(height: Space.xl),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EmailField(controller: _email, autofocus: true),
              const SizedBox(height: Space.lg),
              NewPasswordField(
                controller: _password,
                errorText: _passwordError,
                onChanged: (_) => setState(() => _passwordError = null),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        DeclarationRow(
          text: adultDeclaration,
          value: _adult,
          onChanged: (v) => setState(() => _adult = v),
        ),
        const SizedBox(height: Space.md),
        const SignupAgreement(),
        const SizedBox(height: Space.xl),
        if (_submission.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.lg),
        ],
        PrimaryButton(
          label: 'Criar conta',
          busy: _submission.busy,
          onPressed: _adult && !_submission.blocked ? _submit : null,
        ),
        SubmitHint(declarationHint, visible: !_adult),
        const SizedBox(height: Space.xxl),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Já tem conta?',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: context.palette.muted),
            ),
            TextButton(
              onPressed: () => context.go(Routes.entry),
              child: const Text('Entrar'),
            ),
          ],
        ),
      ],
    ),
  );
}

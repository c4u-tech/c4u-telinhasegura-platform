import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'new_password.dart';
import 'submission.dart';
import 'widgets.dart';

enum _Stage { choosing, done, expired }

/// `/redefinir-senha?token=` from the mailed link.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  final String? token;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _submission = Submission();
  String? _passwordError;
  late var _stage = (widget.token ?? '').isEmpty
      ? _Stage.expired
      : _Stage.choosing;

  @override
  void dispose() {
    _password.dispose();
    _submission.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!longEnough(_password.text)) {
      setState(() => _passwordError = tooShortMessage);
      return;
    }
    final services = AppScope.of(context);
    var expired = false;
    final ok = await _submission.run(
      () => services.auth.confirmPasswordReset(
        token: widget.token!,
        newPassword: _password.text,
      ),
      handle: (e) {
        if (e.code == 'invalid_token') return expired = true;
        final onField = passwordFieldError(e);
        if (onField != null) setState(() => _passwordError = onField);
        return onField != null;
      },
    );
    if (!mounted) return;
    if (expired) return setState(() => _stage = _Stage.expired);
    if (!ok) return;
    TextInput.finishAutofillContext();
    // The server ended every session, this device's included.
    await services.client.forgetSession();
    if (mounted) setState(() => _stage = _Stage.done);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: _submission,
      builder: (context, _) => switch (_stage) {
        _Stage.expired => FieldLayout(
          title: 'Link expirado',
          children: [
            Text(
              'Este link para criar uma senha nova expirou ou já foi usado.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: () => context.go(Routes.forgotPassword),
              child: const Text('Pedir um novo link'),
            ),
          ],
        ),
        _Stage.done => FieldLayout(
          title: 'Senha nova salva',
          rise: true,
          children: [
            const Notice(
              'Pronto. Por segurança, saímos da sua conta em todos os '
              'aparelhos. Entre de novo com a senha nova.',
            ),
            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: () => context.go(Routes.entry),
              child: const Text('Entrar'),
            ),
          ],
        ),
        _Stage.choosing => FieldLayout(
          title: 'Criar senha nova',
          children: [
            AutofillGroup(
              child: NewPasswordField(
                controller: _password,
                label: 'Nova senha',
                errorText: _passwordError,
                onChanged: (_) => setState(() => _passwordError = null),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(height: Space.xl),
            if (_submission.message case final message?) ...[
              ErrorNote(message),
              const SizedBox(height: Space.lg),
            ],
            PrimaryButton(
              label: 'Salvar nova senha',
              busy: _submission.busy,
              onPressed: _submission.blocked ? null : _submit,
            ),
          ],
        ),
      },
    );
  }
}

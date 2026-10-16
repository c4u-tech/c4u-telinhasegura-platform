import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'submission.dart';
import 'widgets.dart';

/// The recovery's check-your-email state, which never says whether the
/// address has an account; "Criar uma senha" shows it too.
const resetLinkSent =
    'Se houver uma conta com esse e-\u2060mail, enviamos um link para criar '
    'uma senha nova. Ele vale por 30 minutos.';

/// `/esqueci-a-senha`: the confirmation never says whether the email has
/// an account.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _submission = Submission();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    _submission.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await _submission.run(
      () => AppScope.of(context).auth.requestPasswordReset(_email.text.trim()),
    );
    if (ok) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: _submission,
      builder: (context, _) => FieldLayout(
        title: 'Esqueci a senha',
        onBack: () => context.go(Routes.emailSignIn),
        children: _sent
            ? [
                const Notice(resetLinkSent),
                const SizedBox(height: Space.xl),
                FilledButton(
                  onPressed: () => context.go(Routes.emailSignIn),
                  child: const Text('Voltar para entrar'),
                ),
              ]
            : [
                Text(
                  'Digite o e-\u2060mail da sua conta. Enviamos um link para você '
                  'criar uma senha nova.',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: Space.xl),
                EmailField(
                  controller: _email,
                  autofocus: true,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: Space.xl),
                if (_submission.message case final message?) ...[
                  ErrorNote(message),
                  const SizedBox(height: Space.lg),
                ],
                PrimaryButton(
                  label: 'Enviar link',
                  busy: _submission.busy,
                  onPressed: _submission.blocked ? null : _submit,
                ),
              ],
      ),
    );
  }
}

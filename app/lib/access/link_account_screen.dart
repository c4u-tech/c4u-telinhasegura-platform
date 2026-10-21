import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../auth/provider_sign_in.dart';
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'provider_signup_screen.dart' show stepExpired;
import 'submission.dart';
import 'widgets.dart';

/// `/vincular-conta`: a Google or Apple login whose email already has an
/// account. Linking always needs an explicit confirmation, offered only as
/// the server allows it.
class LinkAccountScreen extends StatefulWidget {
  const LinkAccountScreen({super.key, required this.step});

  final LinkRequired step;

  @override
  State<LinkAccountScreen> createState() => _LinkAccountScreenState();
}

class _LinkAccountScreenState extends State<LinkAccountScreen> {
  final _password = TextEditingController();
  final _submission = Submission();
  bool _expired = false;

  @override
  void dispose() {
    _password.dispose();
    _submission.dispose();
    super.dispose();
  }

  Future<void> _link({required bool clearPassword}) async {
    final services = AppScope.of(context);
    final ticket = widget.step.ticket;
    final ok = await _submission.run(
      () async {
        final label = await services.deviceLabel.read();
        await (clearPassword
            ? services.auth.linkProviderClearingPassword(
                ticket,
                deviceLabel: label,
              )
            : services.auth.linkProvider(
                ticket,
                password: _password.text,
                deviceLabel: label,
              ));
      },
      handle: (e) {
        if (e.code == 'invalid_credentials') _password.clear();
        return _expired = e.code == 'invalid_token';
      },
    );
    if (!mounted) return;
    if (_expired) return setState(() {});
    if (!ok) return;
    if (!clearPassword) TextInput.finishAutofillContext();
    services.justLinked = true;
    services.pending.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final options = widget.step.options;
    return ListenableBuilder(
      listenable: _submission,
      builder: (context, _) => FieldLayout(
        title: 'Ligar contas',
        onBack: () => context.go(Routes.entry),
        children: _expired
            ? [
                const ErrorNote(stepExpired),
                const SizedBox(height: Space.xl),
                FilledButton(
                  onPressed: () => context.go(Routes.entry),
                  child: const Text('Voltar para o início'),
                ),
              ]
            : [
                Text('Já existe uma conta com', style: text.bodyLarge),
                const SizedBox(height: Space.xs),
                AddressText(widget.step.email, style: text.titleMedium),
                const SizedBox(height: Space.md),
                Text(
                  'Para ligar este login a ela, confirme que a conta é sua.',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: Space.xl),
                if (_submission.message case final message?) ...[
                  ErrorNote(message),
                  const SizedBox(height: Space.lg),
                ],
                if (options.contains(LinkOption.password)) ...[
                  AutofillGroup(
                    child: PasswordField(
                      controller: _password,
                      onSubmitted: (_) => _link(clearPassword: false),
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  PrimaryButton(
                    label: 'Ligar e entrar',
                    busy: _submission.busy,
                    onPressed: _submission.blocked
                        ? null
                        : () => _link(clearPassword: false),
                  ),
                ],
                if (options.contains(LinkOption.clearPassword)) ...[
                  if (options.contains(LinkOption.password))
                    const SizedBox(height: Space.xxl),
                  _ClearPasswordChoice(
                    onPressed: _submission.blocked
                        ? null
                        : () => _link(clearPassword: true),
                  ),
                ],
              ],
      ),
    );
  }
}

/// The eviction choice states its consequence before the button that
/// takes it, so no one drops their password without knowing it.
class _ClearPasswordChoice extends StatelessWidget {
  const _ClearPasswordChoice({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = context.palette.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Não sabe a senha?', style: text.titleMedium),
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Você pode ligar sem ela. A senha atual desta conta será apagada '
          'e todos os outros aparelhos sairão da conta. Depois, você entra '
          'com o login que acabou de usar.',
          style: text.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: Space.lg),
        OutlinedButton(
          onPressed: onPressed,
          child: const Text('Apagar a senha e ligar'),
        ),
      ],
    );
  }
}

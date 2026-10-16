import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/provider_sign_in.dart';
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'provider_flow.dart';
import 'signup_screen.dart' show adultDeclaration;
import 'submission.dart';
import 'widgets.dart';

const stepExpired =
    'Este passo expirou. Volte para o início e entre de novo com o mesmo '
    'login.';

/// `/concluir-cadastro`: a new Google or Apple identity confirms the adult
/// declaration on its signup ticket.
class ProviderSignupScreen extends StatefulWidget {
  const ProviderSignupScreen({super.key, required this.step});

  final SignupRequired step;

  @override
  State<ProviderSignupScreen> createState() => _ProviderSignupScreenState();
}

class _ProviderSignupScreenState extends State<ProviderSignupScreen> {
  final _submission = Submission();
  bool _adult = false;
  bool _expired = false;

  @override
  void dispose() {
    _submission.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final services = AppScope.of(context);
    ProviderSignInResult? result;
    await _submission.run(
      () async => result = await services.auth.completeProviderSignup(
        widget.step.ticket,
        adultDeclaration: _adult,
        deviceLabel: await services.deviceLabel.read(),
      ),
      handle: (e) => _expired = e.code == 'invalid_token',
    );
    if (!mounted) return;
    if (_expired) return setState(() {});
    if (result != null) followProviderResult(context, result!);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: _submission,
      builder: (context, _) => FieldLayout(
        title: 'Concluir cadastro',
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
                Text('Você vai criar uma conta com', style: text.bodyLarge),
                const SizedBox(height: Space.xs),
                AddressText(widget.step.email, style: text.titleMedium),
                const SizedBox(height: Space.xl),
                DeclarationRow(
                  text: adultDeclaration,
                  value: _adult,
                  onChanged: (v) => setState(() => _adult = v),
                ),
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
              ],
      ),
    );
  }
}

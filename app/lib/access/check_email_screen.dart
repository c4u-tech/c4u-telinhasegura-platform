import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'submission.dart';
import 'widgets.dart';

const resentNotice =
    'Se houver uma conta esperando confirmação com esse e-\u2060mail, enviamos '
    'um link novo.';

/// `/verifique-seu-email`, step 2 of 2. The signup answer is the same
/// whether or not the email had an account, so this screen says only that
/// an email went out, which is true in every case.
/// What was sent, naming the [address] it went to when known (set with
/// break marks to show, plain to read).
String _sentTo(String? address) => address == null
    ? 'Enviamos um e-\u2060mail com o próximo passo. Abra a mensagem e '
          'toque no link.'
    : 'Enviamos um e-\u2060mail para $address com o próximo passo. Abra a '
          'mensagem e toque no link.';

class CheckEmailScreen extends StatefulWidget {
  const CheckEmailScreen({super.key, required this.email});

  /// The address typed at signup; null after a reload (it never rides in
  /// the URL).
  final String? email;

  @override
  State<CheckEmailScreen> createState() => _CheckEmailScreenState();
}

class _CheckEmailScreenState extends State<CheckEmailScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _submission = Submission();
  bool _resent = false;

  @override
  void dispose() {
    _email.dispose();
    _submission.dispose();
    super.dispose();
  }

  Future<void> _resend() async {
    final ok = await _submission.run(
      () => AppScope.of(context).auth.resendVerification(_email.text.trim()),
    );
    if (ok) setState(() => _resent = true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final known = widget.email;
    return ListenableBuilder(
      listenable: _submission,
      builder: (context, _) => FieldLayout(
        title: 'Confira seu e-\u2060mail',
        children: [
          const StepMarks(step: 2, of: 2),
          const SizedBox(height: Space.xl),
          Text(
            _sentTo(known == null ? null : addressBreaks(known)),
            semanticsLabel: _sentTo(known),
            style: text.bodyLarge,
          ),
          const SizedBox(height: Space.md),
          Text(
            'Não chegou em alguns minutos? Confira a caixa de spam, ou peça '
            'de novo.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: Space.xl),
          if (known == null) ...[
            EmailField(controller: _email),
            const SizedBox(height: Space.lg),
          ],
          if (_submission.message case final message?) ...[
            ErrorNote(message),
            const SizedBox(height: Space.lg),
          ] else if (_resent) ...[
            const Notice(resentNotice),
            const SizedBox(height: Space.lg),
          ],
          OutlinedButton(
            onPressed: _submission.blocked ? null : _resend,
            child: const Text('Reenviar e-\u2060mail'),
          ),
          const SizedBox(height: Space.md),
          TextButton(
            onPressed: () => context.go(Routes.entry),
            child: const Text('Voltar para o início'),
          ),
        ],
      ),
    );
  }
}

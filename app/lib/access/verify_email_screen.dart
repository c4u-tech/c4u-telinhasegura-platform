import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/api_client.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'check_email_screen.dart' show resentNotice;
import 'submission.dart';
import 'widgets.dart';

enum _Stage { confirming, confirmed, expired, failed }

/// `/verificar-email?token=` from the mailed link: confirms once, then
/// celebrates quietly with "o sol sobe".
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.token});

  final String? token;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _confirm = Submission();
  final _resend = Submission();
  final _email = TextEditingController();
  var _stage = _Stage.confirming;
  bool _resent = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final token = widget.token;
    if (token == null || token.isEmpty) {
      _stage = _Stage.expired;
    } else {
      _run(token);
    }
  }

  Future<void> _run(String token) async {
    setState(() => _stage = _Stage.confirming);
    var expired = false;
    final ok = await _confirm.run(
      () => AppScope.of(context).auth.confirmEmail(token),
      handle: (e) => expired = e.code == 'invalid_token',
    );
    if (!mounted) return;
    setState(
      () => _stage = ok
          ? _Stage.confirmed
          : expired
          ? _Stage.expired
          : _Stage.failed,
    );
  }

  Future<void> _resendLink() async {
    final ok = await _resend.run(
      () => AppScope.of(context).auth.resendVerification(_email.text.trim()),
    );
    if (ok) setState(() => _resent = true);
  }

  @override
  void dispose() {
    _confirm.dispose();
    _resend.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final signedIn =
        AppScope.of(context).client.status.value == AuthStatus.signedIn;
    return ListenableBuilder(
      listenable: Listenable.merge([_confirm, _resend]),
      builder: (context, _) => switch (_stage) {
        _Stage.confirming => const FieldLayout(
          title: 'Confirmando seu e-\u2060mail',
          children: [Center(child: CircularProgressIndicator())],
        ),
        _Stage.confirmed => FieldLayout(
          title: 'E-\u2060mail confirmado',
          rise: true,
          children: [
            Notice(
              signedIn
                  ? 'Tudo certo. Agora você pode cadastrar a sua família.'
                  : 'Tudo certo. Entre para cadastrar a sua família.',
            ),
            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: () =>
                  context.go(signedIn ? Routes.home : Routes.entry),
              child: Text(signedIn ? 'Continuar' : 'Entrar'),
            ),
          ],
        ),
        _Stage.expired => FieldLayout(
          title: 'Link expirado',
          children: [
            Text(
              'Este link de confirmação expirou ou já foi usado. Digite seu '
              'e-\u2060mail para receber um novo.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: Space.xl),
            EmailField(controller: _email),
            const SizedBox(height: Space.lg),
            if (_resend.message case final message?) ...[
              ErrorNote(message),
              const SizedBox(height: Space.lg),
            ] else if (_resent) ...[
              const Notice(resentNotice),
              const SizedBox(height: Space.lg),
            ],
            PrimaryButton(
              label: 'Reenviar e-\u2060mail',
              busy: _resend.busy,
              onPressed: _resend.blocked ? null : _resendLink,
            ),
          ],
        ),
        _Stage.failed => FieldLayout(
          title: 'Confirmando seu e-\u2060mail',
          children: [
            ErrorNote(_confirm.message ?? ''),
            const SizedBox(height: Space.lg),
            PrimaryButton(
              label: 'Tentar de novo',
              onPressed: _confirm.blocked ? null : () => _run(widget.token!),
            ),
          ],
        ),
      },
    );
  }
}

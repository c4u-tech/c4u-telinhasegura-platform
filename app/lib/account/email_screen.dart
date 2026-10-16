import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family_model.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'account_write.dart';

/// The done state: the same words whether or not [next] already has an
/// account, since the server answers alike and mails that address
/// instead. [current] stays until the link is opened.
String emailLinkSent(String next, String? current) =>
    'Enviamos um link para $next. Seu e-⁠mail continua '
    '${current ?? 'o atual'} até você abrir o link.';

/// What follows the request, said before anything was sent.
const newEmailHelper =
    'Vamos enviar um link para o endereço novo. A troca vale quando você '
    'abrir o link.';

/// `/conta/email`: one new address, confirmed by a mailed link.
/// It works without a family and with
/// the email still unverified, since fixing a typo'd address is the point.
class EmailScreen extends StatefulWidget {
  const EmailScreen({super.key});

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  final _email = TextEditingController();
  late final FamilyModel _model;
  late final AccountWrite _write;
  bool _started = false;
  String? _fieldError;
  String? _sentTo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    _model = services.familyModel;
    _write = AccountWrite(
      confirm: () => confirmItsYou(context),
      signOut: services.client.forgetSession,
    );
    // The current address comes with the family's first read.
    scheduleMicrotask(_model.load);
    _email.addListener(() {
      if (_fieldError != null) setState(() => _fieldError = null);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _write.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final next = _email.text.trim();
    if (next.isEmpty) return setState(() => _fieldError = Copy.newEmailInvalid);
    final auth = AppScope.of(context).auth;
    final ok = await _write.write(
      () => auth.requestEmailChange(next),
      handle: (e) {
        if (e.code != 'validation') return false;
        setState(() => _fieldError = Copy.newEmailInvalid);
        return true;
      },
    );
    if (ok && mounted) setState(() => _sentTo = next);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _write]),
    builder: (context, _) => FieldLayout(
      title: 'Trocar o e-⁠mail',
      onBack: () => context.go(Routes.account),
      children: switch (_sentTo) {
        final next? => [
          Notice(
            emailLinkSent(
              addressBreaks(next),
              _model.email == null ? null : addressBreaks(_model.email!),
            ),
            semanticsLabel: emailLinkSent(next, _model.email),
          ),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: () => context.go(Routes.account),
            child: const Text('Voltar para sua conta'),
          ),
        ],
        null => _form(),
      },
    ),
  );

  List<Widget> _form() {
    final text = Theme.of(context).textTheme;
    final current = _model.email;
    return [
      if (current != null) ...[
        Text(
          'Seu e-⁠mail agora',
          style: text.bodyMedium?.copyWith(color: context.palette.muted),
        ),
        const SizedBox(height: Space.xs),
        AddressText(current, style: text.titleMedium),
        const SizedBox(height: Space.xl),
      ],
      EmailField(
        controller: _email,
        label: 'Novo e-⁠mail',
        errorText: _fieldError,
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: Space.sm),
      Text(
        newEmailHelper,
        style: text.bodySmall?.copyWith(color: context.palette.muted),
      ),
      const SizedBox(height: Space.xl),
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Enviar link',
        busy: _write.busy,
        onPressed: _write.blocked ? null : _submit,
      ),
    ];
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/provider_sign_in.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/services.dart';
import 'copy.dart';
import 'provider_flow.dart';
import 'submission.dart';
import 'widgets.dart';

const reauthReason = 'Esta ação pede uma confirmação recente da sua conta.';

/// Asks the guardian to confirm it is them, with the password or the
/// account's Google or Apple login. True once
/// the API accepted it; false when cancelled. The caller retries its
/// action, once.
Future<bool> confirmItsYou(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    useSafeArea: false,
    barrierDismissible: false,
    barrierColor: BrandColors.dark.withValues(alpha: 0.6),
    builder: (_) => const ReauthPrompt(),
  );
  return confirmed ?? false;
}

/// The prompt itself: a whole task screen over the one it interrupts, so
/// it keeps the ink field and the 400 px column. The password lives only
/// in its field and goes when the prompt closes.
class ReauthPrompt extends StatefulWidget {
  const ReauthPrompt({super.key});

  @override
  State<ReauthPrompt> createState() => _ReauthPromptState();
}

class _ReauthPromptState extends State<ReauthPrompt> {
  final _password = TextEditingController();
  final _submission = Submission();
  StreamSubscription<String>? _googleTokens;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _googleTokens ??= AppScope.of(context).googleWeb
        ?.idTokens()
        .listen((token) {
          if (mounted) _offer(IdentityProvider.google, token);
        });
  }

  @override
  void dispose() {
    _googleTokens?.cancel();
    _password.dispose();
    _submission.dispose();
    super.dispose();
  }

  void _close(bool confirmed) => Navigator.of(context).pop(confirmed);

  Future<void> _confirm() async {
    if (_password.text.isEmpty) return;
    final auth = AppScope.of(context).auth;
    final ok = await _submission.run(
      () => auth.reauthenticate(_password.text),
      handle: (e) {
        if (e.code == 'invalid_credentials') _password.clear();
        return false;
      },
    );
    if (ok && mounted) _close(true);
  }

  /// Asks the platform for a token; a cancelled sheet stays quiet.
  Future<void> _withProvider(IdentityProvider provider) async {
    final providers = AppScope.of(context).providers;
    String? token;
    final asked = await _submission.run(
      () async => token = await providers.idToken(provider),
    );
    if (asked && token != null && mounted) await _offer(provider, token!);
  }

  Future<void> _offer(IdentityProvider provider, String token) async {
    final auth = AppScope.of(context).auth;
    final ok = await _submission.run(
      () => auth.reauthenticateWithProvider(provider, token),
      overrides: const {
        'invalid_credentials': Copy.otherProviderAccount,
        'invalid_token': providerTokenRefused,
      },
    );
    if (ok && mounted) _close(true);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Dialog.fullscreen(
      backgroundColor: context.palette.ground,
      child: ListenableBuilder(
        listenable: Listenable.merge([_submission, _password]),
        builder: (context, _) {
          final idle = !_submission.blocked;
          return FieldLayout(
            title: 'Confirme que é você',
            onBack: () => _close(false),
            children: [
              Text(reauthReason, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: Space.xl),
              if (_submission.message case final message?) ...[
                ErrorNote(message),
                const SizedBox(height: Space.lg),
              ],
              AutofillGroup(
                child: PasswordField(
                  controller: _password,
                  onSubmitted: (_) => _confirm(),
                ),
              ),
              const SizedBox(height: Space.lg),
              PrimaryButton(
                label: 'Confirmar',
                busy: _submission.busy,
                onPressed: idle && _password.text.isNotEmpty ? _confirm : null,
              ),
              if (offersProviders(services)) ...[
                const OrDivider(),
                ProviderChoices(onPressed: idle ? _withProvider : null),
              ],
              const SizedBox(height: Space.xxl),
              QuietAction(label: 'Cancelar', onPressed: () => _close(false)),
            ],
          );
        },
      ),
    );
  }
}

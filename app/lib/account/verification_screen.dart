import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/confirm.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/challenge.dart';
import '../staff/mfa.dart';
import 'account_write.dart';
import 'mfa_words.dart';
import 'recovery_codes_view.dart';

/// What assistive technology hears while the status loads.
const loadingMfa = 'Carregando a verificação';

/// `/conta/verificacao`: a platform role holder's second factor.
/// Not enrolled, what it is and "Ativar"; enrolled,
/// since when, the recovery codes left and "Gerar novos códigos", which
/// ends on the codes screen. No way to turn the factor off: only the CLI
/// resets it. The status is read once the roles show one, and again on
/// coming back from the enrollment.
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key, this.notice, this.elevate});

  /// A calm line to show, such as "Verificação ativada.".
  final String? notice;

  /// Opens the MFA challenge when new codes answer `elevation_required`;
  /// [askChallenge] by default.
  final Future<bool> Function()? elevate;

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late final FamilyModel _model;
  late final AccountWrite _write;
  late final GoRouterDelegate _router;
  bool _started = false;
  bool _asked = false;
  late bool _away;
  MfaStatus? _status;
  Object? _error;

  /// New recovery codes, held only while their screen shows.
  List<String>? _codes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    _model = services.familyModel;
    _write = AccountWrite(
      confirm: () => confirmItsYou(context),
      elevate: widget.elevate ?? () => askChallenge(context),
      signOut: services.client.forgetSession,
    );
    // Arriving here directly reads the roles; the router decides on them.
    scheduleMicrotask(_model.load);
    _model.addListener(_rolesRead);
    _rolesRead();
    _router = GoRouter.of(context).routerDelegate..addListener(_moved);
    _away = !_here;
  }

  bool get _here => _router.currentConfiguration.uri.path == Routes.accountMfa;

  @override
  void dispose() {
    _model.removeListener(_rolesRead);
    _router.removeListener(_moved);
    _write.dispose();
    super.dispose();
  }

  /// No role, no MFA call: the router sends the guardian to `/conta`.
  void _rolesRead() {
    if (_asked || !(_model.roles?.isNotEmpty ?? false)) return;
    _asked = true;
    _read();
  }

  /// Back from the enrollment, the factor may have changed.
  void _moved() {
    final here = _here;
    if (here && _away && _asked) _read();
    _away = !here;
  }

  Future<void> _read() async {
    final services = AppScope.of(context);
    setState(() {
      _status = null;
      _error = null;
    });
    try {
      final status = await services.mfa.status();
      if (mounted) setState(() => _status = status);
    } on Object catch (e) {
      if (e is ApiError && e.code == 'unauthenticated') {
        unawaited(services.client.forgetSession());
        return;
      }
      if (mounted) setState(() => _error = e);
    }
  }

  /// Confirms, then replaces the codes (re-authentication and the
  /// challenge as the server asks), then shows the new ones.
  Future<void> _regenerate(int left) async {
    final mfa = AppScope.of(context).mfa;
    final confirmed = await confirmDestructive(
      context,
      title: 'Gerar novos códigos?',
      body: [codesEndWords(left)],
      action: 'Gerar novos códigos',
    );
    if (!confirmed || !mounted) return;
    RecoveryCodes? codes;
    final ok = await _write.write(
      () async => codes = await mfa.regenerateRecoveryCodes(),
      overrides: const {'mfa_unavailable': mfaUnavailable},
    );
    if (ok && mounted) setState(() => _codes = codes!.codes);
  }

  void _codesDone() {
    setState(() => _codes = null);
    _read();
  }

  @override
  Widget build(BuildContext context) {
    if (_codes case final codes?) {
      return RecoveryCodesView(codes: codes, onDone: _codesDone);
    }
    return ListenableBuilder(
      listenable: _write,
      builder: (context, _) => FieldLayout(
        title: mfaTitle,
        onBack: () => context.go(Routes.account),
        children: switch ((_status, _error)) {
          (final status?, _) => _view(status),
          (_, final error?) => [
            ErrorNote(
              isMfaUnavailable(error) ? mfaUnavailable : Copy.genericRetry,
            ),
            const SizedBox(height: Space.lg),
            PrimaryButton(label: 'Tentar de novo', onPressed: _read),
          ],
          _ => const [FamilyPlaceholder(label: loadingMfa)],
        },
      ),
    );
  }

  List<Widget> _view(MfaStatus status) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    return [
      if (widget.notice case final notice?) ...[
        Notice(notice),
        const SizedBox(height: Space.xl),
      ],
      if (!status.enrolled) ...[
        for (final line in mfaWhat) ...[
          Text(line, style: text.bodyLarge),
          const SizedBox(height: Space.md),
        ],
        const SizedBox(height: Space.md),
        PrimaryButton(
          label: 'Ativar',
          onPressed: () => context.go(Routes.accountMfaEnroll),
        ),
      ] else ...[
        if (status.enrolledAt case final at?)
          Text(mfaEnrolledSince(at, clock.now()), style: text.titleMedium),
        const SizedBox(height: Space.sm),
        Text(codesLeftWords(status.recoveryCodesLeft), style: text.bodyLarge),
        if (status.recoveryCodesLeft <= codesLow) ...[
          const SizedBox(height: Space.xs),
          Text('Gere novos códigos antes que acabem', style: muted),
        ],
        const SizedBox(height: Space.xl),
        if (_write.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.lg),
        ],
        OutlinedButton(
          onPressed: _write.blocked
              ? null
              : () => _regenerate(status.recoveryCodesLeft),
          child: const Text('Gerar novos códigos'),
        ),
        const SizedBox(height: Space.xxl),
        Text(lostDeviceLine, style: muted),
      ],
    ];
  }
}

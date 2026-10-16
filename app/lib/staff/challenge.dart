import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/reauth_write.dart';
import '../access/widgets.dart';
import '../account/enrollment_screen.dart';
import '../account/mfa_widgets.dart' show codeStyle;
import '../account/mfa_words.dart' show mfaUnavailable;
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../curation/role_gate.dart' show takeLostRole;
import '../shell/routes.dart';
import '../shell/services.dart';
import 'factor_block.dart';
import 'mfa.dart';

const challengeTitle = 'Código do app autenticador';
const challengeLine = 'Digite o código de 6 números que o app mostra agora.';
const recoveryTitle = 'Use um código de recuperação';
const recoveryLabel = 'Código de recuperação';
const recoveryLine =
    'Digite um dos seus códigos de recuperação. Cada um vale uma vez.';
const toRecovery = 'Usar um código de recuperação';
const toApp = 'Usar o app autenticador';

/// A recovery code refused (`mfa_code_invalid`; the app's code is
/// [codeInvalid]).
const recoveryInvalid = 'Esse código não confere ou já foi usado.';

/// The recovery codes left after one was used.
String codesLeftNotice(int n) => switch (n) {
  0 => 'Não restam códigos de recuperação.',
  1 => 'Resta 1 código de recuperação.',
  _ => 'Restam $n códigos de recuperação.',
};

/// Under [codesLeftNotice] while few are left.
const codesLowNotice = 'Gere novos em Sua conta.';

/// From this many codes left, the challenge asks for new ones.
const _codesLow = 3;

/// How a challenge ended, for [askChallenge] to act on; a cancel is
/// null.
sealed class ChallengeEnd {
  const ChallengeEnd();
}

final class ChallengePassed extends ChallengeEnd {
  const ChallengePassed(this.until);

  final DateTime until;
}

final class ChallengeNotEnrolled extends ChallengeEnd {
  const ChallengeNotEnrolled();
}

final class ChallengeRoleLost extends ChallengeEnd {
  const ChallengeRoleLost(this.error);

  final ApiError error;
}

/// Opens the MFA challenge over the screen that [context] belongs to and
/// returns whether it passed: the elevation a staff read or write asks
/// for with `elevation_required`, or the staff routes' gate.
/// False when cancelled. `mfa_not_enrolled` leads into the
/// enrollment, whose completion counts as passing; a lost role goes home
/// with its notice. Screens asking at once share one challenge.
Future<bool> askChallenge(BuildContext context) {
  final services = AppScope.of(context);
  // Asked, the session is not elevated, whatever the app remembered.
  services.elevation.forget();
  return services.elevation.once(askChallenge, () async {
    final end = await showDialog<ChallengeEnd>(
      context: context,
      useSafeArea: false,
      barrierDismissible: false,
      barrierColor: BrandColors.dark.withValues(alpha: 0.6),
      builder: (dialog) => Dialog.fullscreen(
        backgroundColor: dialog.palette.ground,
        child: ChallengeScreen(onClose: (end) => Navigator.of(dialog).pop(end)),
      ),
    );
    switch (end) {
      case ChallengePassed(:final until):
        services.elevation.elevated(until);
        return true;
      case ChallengeNotEnrolled() when context.mounted:
        return enrollFactor(context);
      case ChallengeRoleLost(:final error) when context.mounted:
        takeLostRole(context, error);
        return false;
      default:
        return false;
    }
  });
}

/// Opens the enrollment for a staff read or write refused with
/// `mfa_enrollment_required`, shared by the
/// screens asking at once; true once done.
Future<bool> askEnrollment(BuildContext context) {
  final elevation = AppScope.of(context).elevation..forget();
  return elevation.once(askEnrollment, () => enrollFactor(context));
}

/// A staff screen's write: re-authentication, the challenge and the
/// enrollment, each asked once as the server asks, then the write again,
/// every input kept.
ReauthWrite staffWrite(BuildContext context) => ReauthWrite(
  confirm: () => confirmItsYou(context),
  elevate: () => askChallenge(context),
  enroll: () => askEnrollment(context),
);

/// Takes a staff read's MFA refusal [error], as
/// [takeLostRole] takes a lost role: `elevation_required` opens the
/// challenge and `mfa_enrollment_required` the enrollment; once passed,
/// [again] reads again, and a cancel goes home. Returns whether it took
/// [error]; a screen words anything else itself.
bool takeMfaRefusal(
  BuildContext context,
  Object error, {
  required VoidCallback again,
}) {
  final ask = switch (error) {
    ApiError(code: 'elevation_required') => askChallenge,
    ApiError(code: 'mfa_enrollment_required') => askEnrollment,
    _ => null,
  };
  if (ask == null) return false;
  unawaited(
    ask(context).then((passed) {
      if (!context.mounted) return;
      if (passed) return again();
      context.go(Routes.home);
    }),
  );
  return true;
}

/// The challenge: a full-screen task over the screen that asked, not a
/// route of its own. The six digits from the
/// authenticator, or one recovery code; then [onClose] reports how it
/// ended. A block disables the field, counts down in minutes and shows
/// the way to sign the other devices out, which comes back here. The
/// codes live only in this state.
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key, required this.onClose});

  final ValueChanged<ChallengeEnd?> onClose;

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  final _code = TextEditingController();
  final _recovery = TextEditingController();
  bool _usingRecovery = false;
  bool _busy = false;
  String? _fieldError;
  String? _note;
  bool _offline = false;

  /// While the factor is blocked.
  final _block = FactorBlock();

  /// The challenge passed with a recovery code, whose count shows first.
  Elevation? _passed;

  @override
  void dispose() {
    _block.dispose();
    _code.dispose();
    _recovery.dispose();
    super.dispose();
  }

  void _close(ChallengeEnd? end) => widget.onClose(end);

  void _back() => _close(switch (_passed) {
    final e? => ChallengePassed(e.elevatedUntil),
    null => null,
  });

  String get _typed => (_usingRecovery ? _recovery : _code).text.trim();

  bool get _ready =>
      !_busy &&
      !_block.active &&
      (_usingRecovery ? _typed.isNotEmpty : _typed.length == 6);

  void _swap() => setState(() {
    _usingRecovery = !_usingRecovery;
    _fieldError = null;
  });

  Future<void> _submit() async {
    if (!_ready) return;
    final services = AppScope.of(context);
    final recovery = _usingRecovery;
    final typed = _typed;
    setState(() {
      _busy = true;
      _fieldError = null;
      _note = null;
      _offline = false;
    });
    try {
      final elevation = recovery
          ? await services.mfa.challenge(recoveryCode: typed)
          : await services.mfa.challenge(code: typed);
      if (!mounted) return;
      if (!recovery) return _close(ChallengePassed(elevation.elevatedUntil));
      _passed = elevation;
    } on ApiError catch (e) {
      switch (e.code) {
        case 'mfa_code_invalid':
          _fieldError = recovery ? recoveryInvalid : codeInvalid;
        case 'rate_limited':
          // The code typed has expired by the end: the field reopens
          // empty, never inviting a wasted attempt toward the next block.
          _code.clear();
          _recovery.clear();
          _block.start(e.retryAfter ?? const Duration(seconds: 60));
        case 'mfa_not_enrolled':
          return _close(const ChallengeNotEnrolled());
        case 'not_staff' || 'not_admin' || 'not_moderator':
          return _close(ChallengeRoleLost(e));
        case 'unauthenticated':
          // Signed out elsewhere: the router lands on the entry.
          unawaited(services.client.forgetSession());
          return _close(null);
        default:
          _note = Copy.forError(
            e,
            overrides: {'mfa_unavailable': mfaUnavailable},
          );
      }
    } on Object {
      _note = Copy.genericRetry;
      _offline = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: ListenableBuilder(
      listenable: Listenable.merge([_code, _recovery, _block]),
      builder: (context, _) => FieldLayout(
        title: _usingRecovery ? recoveryTitle : challengeTitle,
        onBack: _back,
        children: switch (_passed) {
          final passed? => _done(passed),
          null => _form(),
        },
      ),
    ),
  );

  /// After a recovery code: how many are left, then on.
  List<Widget> _done(Elevation passed) => [
    Notice(codesLeftNotice(passed.recoveryCodesLeft)),
    if (passed.recoveryCodesLeft <= _codesLow) ...[
      const SizedBox(height: Space.sm),
      const Notice(codesLowNotice),
    ],
    const SizedBox(height: Space.xl),
    PrimaryButton(label: 'Continuar', onPressed: _back),
  ];

  List<Widget> _form() {
    final text = Theme.of(context).textTheme;
    final blocked = _block.minutes;
    return [
      Text(
        _usingRecovery ? recoveryLine : challengeLine,
        style: text.bodyLarge?.copyWith(color: context.palette.muted),
      ),
      const SizedBox(height: Space.xl),
      if (blocked != null) ...[
        BlockedNote(minutes: blocked),
        const SizedBox(height: Space.xl),
      ] else if (_note case final note?) ...[
        ErrorNote(note),
        if (_offline) ...[
          const SizedBox(height: Space.sm),
          QuietAction(label: 'Tentar de novo', onPressed: _submit),
        ],
        const SizedBox(height: Space.lg),
      ],
      if (_usingRecovery)
        _field(
          key: const ValueKey('recovery'),
          controller: _recovery,
          label: recoveryLabel,
          keyboard: TextInputType.visiblePassword,
          formatters: const [],
        )
      else
        _field(
          key: const ValueKey('code'),
          controller: _code,
          label: 'Código de 6 números',
          keyboard: TextInputType.number,
          formatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          autofill: const [AutofillHints.oneTimeCode],
        ),
      const SizedBox(height: Space.lg),
      PrimaryButton(
        label: 'Confirmar',
        busy: _busy,
        onPressed: _ready ? _submit : null,
      ),
      const SizedBox(height: Space.lg),
      QuietAction(
        label: _usingRecovery ? toApp : toRecovery,
        onPressed: _busy ? null : _swap,
      ),
    ];
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    required TextInputType keyboard,
    required List<TextInputFormatter> formatters,
    List<String>? autofill,
  }) => TextField(
    key: key,
    controller: controller,
    enabled: !_block.active,
    autofocus: true,
    keyboardType: keyboard,
    autofillHints: autofill,
    autocorrect: false,
    enableSuggestions: false,
    textCapitalization: TextCapitalization.characters,
    inputFormatters: formatters,
    textInputAction: TextInputAction.done,
    style: codeStyle(context),
    onChanged: (_) {
      if (_fieldError != null) setState(() => _fieldError = null);
    },
    onSubmitted: (_) => _submit(),
    decoration: InputDecoration(labelText: label, errorText: _fieldError),
  );
}

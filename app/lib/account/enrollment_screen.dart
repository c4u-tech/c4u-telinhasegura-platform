import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../auth/api_error.dart';
import '../staff/factor_block.dart';
import '../staff/mfa.dart';
import 'account_write.dart';
import 'mfa_widgets.dart';
import 'mfa_words.dart';
import 'recovery_codes_view.dart';

/// The code step's refusal of a wrong code (`mfa_code_invalid`).
const codeInvalid =
    'Esse código não confere. Use o código que aparece agora no app.';

/// The key step's notice after `mfa_not_pending`: the key the app showed
/// was replaced or dropped, and a new one is shown.
const keyRestarted =
    'A chave anterior deixou de valer. Adicione esta nova chave no app.';

/// When the `otpauth://` link opens nothing.
const appNotOpened =
    'Não conseguimos abrir o app autenticador. Copie a chave ou use o QR '
    'code.';

/// What assistive technology hears while the key is asked for.
const loadingKey = 'Preparando a chave';

/// Opens the enrollment over the screen that [context] belongs to, for a
/// staff screen that must stay as it is (a write refused with `mfa_enrollment_required` and repeated after).
/// True once the recovery codes were kept, when the session is already
/// elevated (no challenge follows); false when cancelled, or when the
/// account turned out to be enrolled already.
///
/// A gate that only routes uses [Routes.mfaEnrollment] instead.
Future<bool> enrollFactor(BuildContext context) async {
  final enrolled = await showDialog<bool>(
    context: context,
    useSafeArea: false,
    barrierDismissible: false,
    barrierColor: BrandColors.dark.withValues(alpha: 0.6),
    builder: (dialog) => Dialog.fullscreen(
      backgroundColor: dialog.palette.ground,
      child: EnrollmentScreen(
        onClose: (enrolled) => Navigator.of(dialog).pop(enrolled),
      ),
    ),
  );
  return enrolled ?? false;
}

enum _Step { key, code, codes }

/// `/conta/verificacao/ativar`: the second factor's enrollment, three
/// steps on one route, back stepping back. The key
/// (after a re-authentication), adapted to the width: on a narrow screen
/// the link that opens the authenticator first and the QR on demand; on a
/// wide one the QR first. Then the six-digit code; then the ten recovery
/// codes. The secret and the codes live only in this state: never in a
/// route, storage or a log.
///
/// It ends on [then], the staff screen that asked for it, already
/// checked by [Routes.staffReturn]; without one, on `/conta/verificacao`
/// with "Verificação ativada.". Cancelled, it returns home when a staff
/// screen asked, and to `/conta/verificacao` otherwise. With [onClose]
/// (see [enrollFactor]) it routes nowhere and reports instead.
class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key, this.then, this.onClose});

  final String? then;

  /// Called with true once the codes were kept, false when cancelled.
  final ValueChanged<bool>? onClose;

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  late final FamilyModel _model;
  late final AccountWrite _start;
  late final AccountWrite _confirm;
  final _code = TextEditingController();

  /// While the factor is blocked (`rate_limited`).
  final _block = FactorBlock();
  bool _started = false;
  bool _asked = false;
  _Step _step = _Step.key;
  MfaEnrollment? _enrollment;
  List<String>? _codes;
  bool _qr = false;
  bool _copied = false;
  bool _notOpened = false;
  bool _restarted = false;
  String? _codeError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    _model = services.familyModel;
    AccountWrite write() => AccountWrite(
      confirm: () => confirmItsYou(context),
      signOut: services.client.forgetSession,
    );
    _start = write();
    _confirm = write();
    scheduleMicrotask(_model.load);
    _model.addListener(_rolesRead);
    _rolesRead();
  }

  @override
  void dispose() {
    _model.removeListener(_rolesRead);
    _start.dispose();
    _confirm.dispose();
    _code.dispose();
    _block.dispose();
    super.dispose();
  }

  /// No role, no MFA call: the router sends the guardian to `/conta`.
  void _rolesRead() {
    if (_asked || !(_model.roles?.isNotEmpty ?? false)) return;
    _asked = true;
    scheduleMicrotask(_begin);
  }

  /// Asks for a key, within re-authentication.
  Future<void> _begin() async {
    final mfa = AppScope.of(context).mfa;
    var enrolled = false;
    MfaEnrollment? enrollment;
    final ok = await _start.write(
      () async => enrollment = await mfa.startEnrollment(),
      overrides: const {'mfa_unavailable': mfaUnavailable},
      handle: (e) => enrolled = e.code == 'mfa_already_enrolled',
    );
    if (!mounted) return;
    if (enrolled) {
      return switch (widget.onClose) {
        final close? => close(false),
        null => context.go(Routes.accountMfa),
      };
    }
    // A cancelled re-authentication leaves no message: the errand ends.
    if (!ok && _start.message == null) return _cancel();
    setState(() => _enrollment = enrollment);
  }

  void _cancel() => switch (widget.onClose) {
    final close? => close(false),
    null => context.go(widget.then == null ? Routes.accountMfa : Routes.home),
  };

  void _done() => switch (widget.onClose) {
    final close? => close(true),
    null => switch (widget.then) {
      final then? => context.go(then),
      null => context.go(Routes.accountMfa, extra: mfaEnrolled),
    },
  };

  void _back() => switch (_step) {
    _Step.code => setState(() => _step = _Step.key),
    _ => _cancel(),
  };

  Future<void> _openApp(MfaEnrollment enrollment) async {
    final links = AppScope.of(context).links;
    setState(() => _notOpened = false);
    var opened = false;
    try {
      opened = await links.open(Uri.parse(enrollment.otpauthUri));
    } on Object {
      opened = false;
    }
    if (mounted && !opened) setState(() => _notOpened = true);
  }

  Future<void> _copyKey(MfaEnrollment enrollment) async {
    await Clipboard.setData(ClipboardData(text: enrollment.secret));
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _confirmCode() async {
    final mfa = AppScope.of(context).mfa;
    var notPending = false;
    RecoveryCodes? codes;
    Duration? blocked;
    setState(() => _codeError = null);
    final ok = await _confirm.write(
      () async {
        try {
          codes = await mfa.confirmEnrollment(_code.text);
        } on ApiError catch (e) {
          // The factor's block, as the challenge shows it, not
          // the form's countdown in seconds.
          if (e.code != 'rate_limited') rethrow;
          blocked = e.retryAfter ?? const Duration(seconds: 60);
        }
      },
      overrides: const {'mfa_unavailable': mfaUnavailable},
      handle: (e) {
        switch (e.code) {
          case 'mfa_code_invalid':
            _codeError = codeInvalid;
            return true;
          case 'mfa_not_pending':
            return notPending = true;
        }
        return false;
      },
    );
    if (!mounted) return;
    if (blocked case final wait?) {
      // Expired by the end: the field reopens empty.
      _code.clear();
      return _block.start(wait);
    }
    if (ok) {
      // The confirm elevated the session: the staff gate need not ask.
      if (codes!.elevatedUntil case final until?) {
        AppScope.of(context).elevation.elevated(until);
      }
      // The secret goes as the codes come: neither is needed again.
      _code.clear();
      setState(() {
        _enrollment = null;
        _codes = codes!.codes;
        _step = _Step.codes;
      });
    } else if (notPending) {
      _code.clear();
      setState(() {
        _enrollment = null;
        _restarted = true;
        _copied = false;
        _qr = false;
        _step = _Step.key;
      });
      await _begin();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if ((_step, _codes) case (_Step.codes, final codes?)) {
      return RecoveryCodesView(codes: codes, onDone: _done);
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([_start, _confirm, _code, _block]),
        builder: (context, _) => FieldLayout(
          title: _step == _Step.code
              ? 'Digite o código que o app mostra'
              : 'Conecte o app autenticador',
          onBack: _back,
          children: switch ((_step, _enrollment)) {
            (_Step.code, _) => _codeStep(),
            (_, final enrollment?) => _keyStep(enrollment),
            _ when _start.message != null => [
              ErrorNote(_start.message!),
              const SizedBox(height: Space.lg),
              PrimaryButton(
                label: 'Tentar de novo',
                busy: _start.busy,
                onPressed: _start.blocked ? null : _begin,
              ),
            ],
            _ => const [FamilyPlaceholder(label: loadingKey)],
          },
        ),
      ),
    );
  }

  List<Widget> _keyStep(MfaEnrollment enrollment) {
    final text = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= FieldSizes.wideBreakpoint;
    final groups = keyGroups(enrollment.secret);
    final qr = KeyQr(uri: enrollment.otpauthUri);
    void toCode() => setState(() => _step = _Step.code);
    return [
      if (_restarted) ...[
        const Notice(keyRestarted),
        const SizedBox(height: Space.lg),
      ],
      Text(
        wide
            ? 'Escaneie o QR code com o app autenticador do seu celular, ou '
                  'digite a chave.'
            : 'Adicione esta chave ao app autenticador do seu celular.',
        style: text.bodyLarge,
      ),
      const SizedBox(height: Space.xl),
      if (wide) ...[
        qr,
        const SizedBox(height: Space.xl),
      ] else ...[
        if (_notOpened) ...[
          const ErrorNote(appNotOpened),
          const SizedBox(height: Space.lg),
        ],
        PrimaryButton(
          label: 'Abrir no app autenticador',
          onPressed: () => _openApp(enrollment),
        ),
        const SizedBox(height: Space.lg),
        // Revealed above the key, which its label says is below it.
        if (_qr) ...[
          qr,
          const SizedBox(height: Space.lg),
        ] else
          QuietAction(
            label: 'Mostrar QR code',
            onPressed: () => setState(() => _qr = true),
          ),
        const SizedBox(height: Space.sm),
      ],
      CodeBlock(
        child: Text(
          groups.join(' '),
          style: codeStyle(context),
          semanticsLabel: 'Chave: ${spokenGroups(groups)}',
        ),
      ),
      const SizedBox(height: Space.sm),
      QuietAction(label: 'Copiar chave', onPressed: () => _copyKey(enrollment)),
      if (_copied) const Notice('Chave copiada'),
      const SizedBox(height: Space.xl),
      if (wide)
        PrimaryButton(label: 'Já adicionei', onPressed: toCode)
      else
        OutlinedButton(onPressed: toCode, child: const Text('Já adicionei')),
    ];
  }

  List<Widget> _codeStep() {
    final blocked = _block.minutes;
    final style = codeStyle(context);
    return [
      if (blocked != null) ...[
        BlockedNote(minutes: blocked),
        const SizedBox(height: Space.lg),
      ] else if (_confirm.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      TextField(
        controller: _code,
        enabled: blocked == null,
        autofocus: true,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        textInputAction: TextInputAction.done,
        style: style,
        onChanged: (_) {
          if (_codeError != null) setState(() => _codeError = null);
        },
        onSubmitted: (_) {
          if (_ready) _confirmCode();
        },
        decoration: InputDecoration(
          labelText: 'Código de 6 números',
          errorText: _codeError,
        ),
      ),
      const SizedBox(height: Space.lg),
      PrimaryButton(
        label: 'Confirmar',
        busy: _confirm.busy,
        onPressed: _ready ? _confirmCode : null,
      ),
    ];
  }

  bool get _ready =>
      _code.text.length == 6 && !_confirm.blocked && !_block.active;
}

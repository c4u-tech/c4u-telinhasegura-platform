import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../parental/app_mode.dart';
import '../shell/routes.dart';
import '../shell/services.dart';

const _whatLinkingDoes =
    'Depois de vinculado, este aparelho só abre o modo criança, para a '
    'criança do código. Gere o código no aparelho do adulto, em Modo '
    'criança.';

const _signOutFirst =
    'Saia da conta antes de vincular este aparelho. O aparelho de uma '
    'criança não fica com a conta de um adulto.';

/// The device label's limit, as the backend counts it (runes, after
/// trimming).
const kMaxDeviceLabel = 40;

const deviceLabelGuidance = 'Use de 1 a $kMaxDeviceLabel\u00A0caracteres.';

/// What the code field asks for, met once 8 characters are in.
const codeGuidance = 'Os 8\u00A0caracteres que aparecem no aparelho do adulto.';

final _control = RegExp(r'[\u0000-\u001F\u007F-\u009F]');

/// The label to send, trimmed, or null while it does not fit: 1 to 40
/// characters, no control characters. The server stays the
/// authority.
String? deviceLabelOf(String text) {
  final label = text.trim();
  final length = label.runes.length;
  return length >= 1 && length <= kMaxDeviceLabel && !_control.hasMatch(label)
      ? label
      : null;
}

/// A link code's characters, upper case, separators and anything else
/// dropped, at most 8.
String _codeChars(String text) {
  final chars = text.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
  return chars.length > 8 ? chars.substring(0, 8) : chars;
}

/// The code as the field shows it: two groups of four, `ABCD-1234`, as
/// the guardian's screen does.
String groupedCode(String text) {
  final chars = _codeChars(text);
  return chars.length > 4
      ? '${chars.substring(0, 4)}-${chars.substring(4)}'
      : chars;
}

/// Takes lower case, spaces and hyphens and shows two groups of four,
/// keeping the caret after the same character. What it shows is
/// what is sent: the server normalizes it.
class LinkCodeFormatter extends TextInputFormatter {
  const LinkCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = groupedCode(newValue.text);
    final caret = newValue.selection.isValid
        ? newValue.selection.extentOffset.clamp(0, newValue.text.length)
        : newValue.text.length;
    final before = _codeChars(newValue.text.substring(0, caret)).length;
    final offset = (before > 4 ? before + 1 : before).clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// `/vincular-aparelho`: links the child's own Android or iOS device with
/// the guardian's code, adult-facing on the cream
/// ground. The code may come from the deep link, read once and dropped
/// from the location. On success the mode moves to the linked
/// device's and the router lands on `/crianca`, whose band growing into
/// the child's screen is the confirmation. A refusal keeps what was typed.
class RedeemScreen extends StatefulWidget {
  const RedeemScreen({super.key, this.code});

  /// The `codigo` of the deep link, when present.
  final String? code;

  @override
  State<RedeemScreen> createState() => _RedeemScreenState();
}

class _RedeemScreenState extends State<RedeemScreen> {
  final _code = TextEditingController();
  final _label = TextEditingController();
  final _submission = Submission();

  /// The server refused the label (`validation`), until it is edited.
  bool _labelRefused = false;

  /// The device holds a guardian session.
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _take(widget.code);
  }

  @override
  void didUpdateWidget(RedeemScreen old) {
    super.didUpdateWidget(old);
    // The link opened again while the screen was open.
    if (widget.code != old.code) _take(widget.code);
  }

  /// Fills the field from the link, then replaces the location without
  /// it, so the code is not kept in the history.
  void _take(String? code) {
    if (code == null) return;
    _code.text = groupedCode(code);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) GoRouter.of(context).go(Routes.redeem);
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _label.dispose();
    _submission.dispose();
    super.dispose();
  }

  bool get _ready =>
      _codeChars(_code.text).length == 8 && deviceLabelOf(_label.text) != null;

  Future<void> _redeem() async {
    final label = deviceLabelOf(_label.text);
    if (label == null) return;
    final services = AppScope.of(context);
    var signedIn = false;
    await _submission.run(
      () async {
        try {
          await services.appMode.redeem(code: _code.text, label: label);
        } on SignedInDevice {
          signedIn = true;
        }
      },
      overrides: Copy.linkCode,
      handle: (e) {
        if (e.code != 'validation') return false;
        setState(() => _labelRefused = true);
        return true;
      },
    );
    if (mounted && signedIn) setState(() => _signedIn = true);
  }

  Future<void> _signOut() async {
    final services = AppScope.of(context);
    final ok = await _submission.run(services.auth.signOut);
    if (mounted && ok) setState(() => _signedIn = false);
  }

  String? get _labelError {
    if (_labelRefused) {
      return 'Confira o nome do aparelho: use de 1 a '
          '$kMaxDeviceLabel\u00A0caracteres.';
    }
    if (_control.hasMatch(_label.text)) {
      return 'O nome tem um caractere que não pode ser usado. Digite de '
          'novo.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_submission, _code, _label]),
    builder: (context, _) {
      final idle = !_submission.blocked;
      return FieldLayout(
        title: 'Vincular este aparelho',
        onBack: () => context.go(Routes.entry),
        children: [
          Text(_whatLinkingDoes, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: Space.xl),
          TextField(
            controller: _code,
            enabled: idle,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            inputFormatters: const [LinkCodeFormatter()],
            onChanged: (_) => _submission.clearMessage(),
            decoration: InputDecoration(
              labelText: 'Código',
              hintText: 'XXXX-XXXX',
              // A module beside it, as beside the name's guidance, so both
              // helpers start on one line.
              helper: Guidance(
                text: codeGuidance,
                met: _codeChars(_code.text).length == 8,
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _label,
            enabled: idle,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            // Room to type past the limit and see the guidance empty.
            inputFormatters: [
              LengthLimitingTextInputFormatter(kMaxDeviceLabel * 2),
            ],
            onChanged: (_) {
              _submission.clearMessage();
              if (_labelRefused) setState(() => _labelRefused = false);
            },
            onSubmitted: (_) {
              if (_ready && idle && !_signedIn) _redeem();
            },
            decoration: InputDecoration(
              labelText: 'Nome do aparelho',
              hintText: 'Ex.: Tablet da Ana',
              errorText: _labelError,
              errorMaxLines: 3,
              helper: Guidance(
                text: deviceLabelGuidance,
                met: deviceLabelOf(_label.text) != null,
              ),
            ),
          ),
          const SizedBox(height: Space.xl),
          if (_signedIn) ...[
            const ErrorNote(_signOutFirst),
            if (_submission.message case final message?) ...[
              const SizedBox(height: Space.sm),
              ErrorNote(message),
            ],
            const SizedBox(height: Space.sm),
            QuietAction(
              label: 'Sair da conta',
              busy: _submission.busy,
              onPressed: _signOut,
            ),
            const SizedBox(height: Space.lg),
          ] else if (_submission.message case final message?) ...[
            ErrorNote(message),
            const SizedBox(height: Space.lg),
          ],
          PrimaryButton(
            label: 'Vincular',
            busy: _submission.busy && !_signedIn,
            onPressed: _ready && idle && !_signedIn ? _redeem : null,
          ),
          SubmitHint('Digite o código e o nome do aparelho.', visible: !_ready),
        ],
      );
    },
  );
}

import 'package:flutter/material.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/pin_pad.dart';
import '../design/tokens.dart';
import '../shell/services.dart';

const _wasKidMode =
    'Este aparelho estava no modo criança. Para entrar na área dos adultos, '
    'digite o PIN da família.';

/// `/pin`: the PIN a sign-in owes on a device that was in kid mode.
/// The server checks it; once given, the mode moves
/// to the guardian's and the router lands on the family home. A wrong PIN
/// and a cooldown answer as on the exit gate. The PIN is never
/// kept after its call.
class PinGateScreen extends StatefulWidget {
  const PinGateScreen({super.key});

  @override
  State<PinGateScreen> createState() => _PinGateScreenState();
}

class _PinGateScreenState extends State<PinGateScreen> {
  final _pad = PinPadController();
  final _check = Submission();
  final _signOut = Submission();

  @override
  void dispose() {
    _check.dispose();
    _signOut.dispose();
    _pad.dispose();
    super.dispose();
  }

  Future<void> _verify(String pin) async {
    await _check.run(() => AppScope.of(context).appMode.verifyPin(pin));
    _pad.clear();
  }

  Future<void> _leave() =>
      _signOut.run(() => AppScope.of(context).auth.signOut());

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_check, _signOut]),
    builder: (context, _) => FieldLayout(
      title: 'Digite o PIN dos pais',
      children: [
        Text(_wasKidMode, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: Space.xl),
        if (_check.message ?? _signOut.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.lg),
        ],
        Center(
          child: PinPad(
            controller: _pad,
            enabled: !_check.blocked && !_signOut.busy,
            onSubmit: _verify,
          ),
        ),
        const SizedBox(height: Space.xxl),
        QuietAction(
          label: 'Sair da conta',
          busy: _signOut.busy,
          onPressed: _check.busy ? null : _leave,
        ),
      ],
    ),
  );
}

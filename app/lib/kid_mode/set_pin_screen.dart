import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/pin_pad.dart';
import '../design/tokens.dart';
import '../family/family_model.dart';
import '../family/family_write.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'kid_mode_screen.dart';

const firstEntry = 'Digite um PIN de 4 a 6 números.';
const firstEntryAgain = 'Digite o PIN de novo, de 4 a 6 números.';
const confirmEntry = 'Digite de novo para confirmar.';
const pinMismatch = 'Os dois PINs não são iguais.';

/// `/modo-crianca/pin`: creates the family PIN, or changes it.
/// The PIN on the pad, then its confirmation; a mismatch or a
/// refused PIN starts over on an empty pad. The PIN lives only in this
/// screen's memory until its call ends, and is never kept after a
/// failure.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key});

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  final _pad = PinPadController();
  late final FamilyModel _model;
  late final FamilyWrite _write;
  bool _started = false;

  /// Whether the family has a PIN: null until read.
  bool? _pinSet;
  bool _readFailed = false;

  /// The first entry, held while the confirmation is typed.
  String? _first;

  /// Back at the first entry after a mismatch or a failed save.
  bool _again = false;
  bool _mismatch = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    _write = FamilyWrite(family: _model, confirm: () => confirmItsYou(context));
    _read();
  }

  @override
  void dispose() {
    _first = null;
    _write.dispose();
    _pad.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() => _readFailed = false);
    try {
      final set = await AppScope.of(context).parental.pinIsSet();
      if (mounted) setState(() => _pinSet = set);
    } on Object catch (e) {
      if (_model.absorb(e) || !mounted) return;
      setState(() => _readFailed = true);
    }
  }

  void _entered(String pin) {
    final first = _first;
    if (first == null) {
      setState(() {
        _first = pin;
        _mismatch = false;
      });
      _write.clearMessage();
      _pad.clear();
    } else if (pin != first) {
      _startOver(mismatch: true);
    } else {
      _save(pin);
    }
  }

  void _startOver({bool mismatch = false}) {
    setState(() {
      _first = null;
      _again = true;
      _mismatch = mismatch;
    });
    if (mismatch) _write.clearMessage();
    _pad.clear();
  }

  Future<void> _save(String pin) async {
    final changed = _pinSet ?? false;
    final ok = await _write.write(
      () => AppScope.of(context).parental.setPin(pin),
      overrides: const {'validation': Copy.pinRule},
    );
    if (!mounted) return;
    if (!ok) return _startOver();
    _first = null;
    context.go(
      Routes.kidMode,
      extra: changed ? PinSaved.changed : PinSaved.created,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _write,
    builder: (context, _) => FieldLayout(
      title: switch (_pinSet) {
        null => 'PIN da família',
        false => 'Criar o PIN',
        true => 'Trocar o PIN',
      },
      onBack: () => context.go(Routes.kidMode),
      children: switch (_pinSet) {
        _? => _entry(),
        null when _readFailed => [
          const ErrorNote(Copy.genericRetry),
          const SizedBox(height: Space.lg),
          PrimaryButton(label: 'Tentar de novo', onPressed: _read),
        ],
        null => const [FamilyPlaceholder(label: 'Carregando o PIN')],
      },
    ),
  );

  List<Widget> _entry() {
    final message = _mismatch ? pinMismatch : _write.message;
    final step = _first != null
        ? confirmEntry
        : _again
        ? firstEntryAgain
        : firstEntry;
    // The intro line, then the error note right above the pad, as on
    // every PIN screen.
    return [
      Semantics(
        liveRegion: true,
        child: Text(step, style: Theme.of(context).textTheme.bodyLarge),
      ),
      const SizedBox(height: Space.xl),
      if (message != null) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      Center(
        child: PinPad(
          controller: _pad,
          enabled: !_write.blocked,
          onSubmit: _entered,
        ),
      ),
    ];
  }
}

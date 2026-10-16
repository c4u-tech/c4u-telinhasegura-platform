import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/widgets.dart';
import 'theme.dart';
import 'tokens.dart';

/// Lets the screen that owns a [PinPad] empty it, after a wrong PIN or
/// between the PIN and its confirmation. It never
/// exposes the digits.
class PinPadController extends ChangeNotifier {
  void clear() => notifyListeners();
}

/// The family PIN pad, one component on both grounds:
/// each typed digit fills a screen module and is never shown or
/// announced; a 3 × 4 keypad of 64 dp keys, plus keyboard digits,
/// Backspace and Enter. It takes the tokens of the ground it sits on:
/// the guardian's, or the kid theme's on ink.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onSubmit,
    this.controller,
    this.enabled = true,
    this.autofocus = true,
  });

  static const minLength = 4;
  static const maxLength = 6;

  /// Called with the digits on "Confirmar" or Enter, from 4 digits on.
  /// The pad keeps them; the owner clears it through [controller].
  final ValueChanged<String> onSubmit;
  final PinPadController? controller;

  /// False while a check is pending or the cooldown runs.
  final bool enabled;
  final bool autofocus;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  // Held only in memory, only while the pad lives.
  var _digits = '';

  static final _keys = {
    for (var d = 0; d <= 9; d++) ...{
      LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + d): '$d',
      LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + d): '$d',
    },
  };

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_clear);
  }

  @override
  void didUpdateWidget(PinPad old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_clear);
      widget.controller?.addListener(_clear);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_clear);
    _digits = '';
    super.dispose();
  }

  void _clear() => setState(() => _digits = '');

  bool get _ready => _digits.length >= PinPad.minLength;

  void _type(String digit) {
    if (_digits.length < PinPad.maxLength) {
      setState(() => _digits += digit);
    }
  }

  void _erase() {
    if (_digits.isNotEmpty) {
      setState(() => _digits = _digits.substring(0, _digits.length - 1));
    }
  }

  void _submit() {
    if (_ready) widget.onSubmit(_digits);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!widget.enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_keys[key] case final digit?) {
      _type(digit);
    } else if (key == LogicalKeyboardKey.backspace) {
      _erase();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _submit();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    Widget digit(String d) => _Key(
      kind: _KeyKind.digit,
      label: d,
      onPressed: on ? () => _type(d) : null,
    );
    Widget row(List<Widget> keys) => Row(
      children: [
        for (final (i, key) in keys.indexed) ...[
          if (i > 0) const SizedBox(width: Space.sm),
          Expanded(child: key),
        ],
      ],
    );
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: FieldSizes.columnMaxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The count only, never the digits.
            Semantics(
              liveRegion: true,
              label:
                  '${_digits.length} de ${PinPad.maxLength} números digitados',
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < PinPad.maxLength; i++) ...[
                      if (i > 0) const SizedBox(width: Space.sm),
                      StateModule(filled: i < _digits.length, height: 18),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.xl),
            for (final (i, line) in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ].indexed) ...[
              if (i > 0) const SizedBox(height: Space.sm),
              row([for (final d in line) digit(d)]),
            ],
            const SizedBox(height: Space.sm),
            row([
              _Key(
                kind: _KeyKind.erase,
                label: 'Apagar',
                icon: Icons.backspace_outlined,
                onPressed: on && _digits.isNotEmpty ? _erase : null,
              ),
              digit('0'),
              _Key(
                kind: _KeyKind.confirm,
                label: 'Confirmar',
                icon: Icons.arrow_forward_rounded,
                onPressed: on && _ready ? _submit : null,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

enum _KeyKind { digit, erase, confirm }

/// One key: a 64 dp screen cut at the 10/33 corner. Read by its digit or
/// its action; never by what has been typed.
class _Key extends StatelessWidget {
  const _Key({
    required this.kind,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final _KeyKind kind;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const height = KidSizes.target;
    // One role per key on both grounds: the digits are the quiet keys (the
    // input tone with an outline stroke), "Confirmar" the one filled key.
    final (fill, ink, side) = switch (kind) {
      _KeyKind.digit => (
        p.input,
        p.text,
        BorderSide(color: p.outline, width: 1.5),
      ),
      _KeyKind.confirm => (p.action, p.onAction, null),
      _KeyKind.erase => (Colors.transparent, p.text, null),
    };
    final disabledFill = kind == _KeyKind.erase
        ? Colors.transparent
        : p.outline.withValues(alpha: 0.32);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(height, height)),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(Space.xs)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(height * Radii.screenRatio),
          ),
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? disabledFill : fill,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? p.text.withValues(alpha: 0.6)
            : ink,
      ),
      overlayColor: WidgetStatePropertyAll(ink.withValues(alpha: 0.12)),
      side: focusRing(
        p,
        onPressed == null && side != null
            ? BorderSide(color: p.outline.withValues(alpha: 0.5), width: 1.5)
            : side,
      ),
      elevation: const WidgetStatePropertyAll(0),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.headlineSmall,
      ),
    );
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: onPressed,
          style: style,
          child: icon == null
              ? Text(label)
              // In step with the digits, up to 200% so it stays in its key.
              : Icon(
                  icon,
                  size: MediaQuery.textScalerOf(context)
                      .clamp(maxScaleFactor: 2)
                      .scale(28),
                ),
        ),
      ),
    );
  }
}

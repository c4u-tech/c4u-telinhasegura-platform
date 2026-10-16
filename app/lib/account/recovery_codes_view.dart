import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../family/confirm.dart';
import '../shell/services.dart';
import 'mfa_widgets.dart';

/// The checkbox "Continuar" waits on.
const codesKept = 'Guardei os códigos em um lugar seguro';

/// The feedback after "Copiar códigos".
const codesCopied = 'Códigos copiados';

/// A recovery code for assistive technology: its two groups, each
/// character by character.
String spokenRecoveryCode(String code) => spokenGroups(code.split('-'));

/// "Guarde seus códigos de recuperação": the ten codes shown once, as
/// `XXXXX-XXXXX` in two columns (one on a narrow screen at large text),
/// read as a list, with "Copiar códigos" (all ten, one per line) and the
/// acknowledgment "Continuar" waits on. Leaving
/// before it (the band's back, the system back or gesture, and, through
/// [AppServices.unkeptCodes], browser back and any other way off the
/// route) asks first. The codes live only in [codes]: never in a route,
/// storage or a log, and gone with the widget.
///
/// The enrollment's last step and the end of "Gerar novos códigos" both
/// show it.
class RecoveryCodesView extends StatefulWidget {
  const RecoveryCodesView({
    super.key,
    required this.codes,
    required this.onDone,
  });

  final List<String> codes;

  /// Called after "Continuar", or once leaving without it was confirmed.
  final VoidCallback onDone;

  @override
  State<RecoveryCodesView> createState() => _RecoveryCodesViewState();
}

class _RecoveryCodesViewState extends State<RecoveryCodesView> {
  AppServices? _services;
  bool _kept = false;
  bool _copied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = AppScope.of(context)..unkeptCodes = _askLeave;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  /// Stops asking: the codes are kept, or leaving was confirmed.
  void _release() {
    final services = _services!;
    if (services.unkeptCodes == _askLeave) services.unkeptCodes = null;
  }

  Future<bool> _askLeave() async {
    final leave = await confirmDestructive(
      context,
      title: 'Sair sem guardar os códigos?',
      body: const [
        'Eles não aparecem de novo. A verificação continua ativada.',
      ],
      action: 'Sair sem guardar',
    );
    if (leave) _release();
    return leave;
  }

  Future<void> _leave() async {
    if (await _askLeave() && mounted) widget.onDone();
  }

  void _continue() {
    _release();
    widget.onDone();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.codes.join('\n')));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: FieldLayout(
        title: 'Guarde seus códigos de recuperação',
        onBack: _leave,
        children: [
          Text(
            'Cada código vale uma vez, se você ficar sem o app autenticador. '
            'Eles não aparecem de novo.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: Space.xl),
          CodeBlock(child: _CodesGrid(codes: widget.codes)),
          const SizedBox(height: Space.lg),
          OutlinedButton(onPressed: _copy, child: const Text('Copiar códigos')),
          if (_copied) ...[
            const SizedBox(height: Space.sm),
            const Notice(codesCopied),
          ],
          const SizedBox(height: Space.lg),
          DeclarationRow(
            text: codesKept,
            value: _kept,
            onChanged: (v) => setState(() => _kept = v),
          ),
          const SizedBox(height: Space.lg),
          PrimaryButton(
            label: 'Continuar',
            onPressed: _kept ? _continue : null,
          ),
          SubmitHint(declarationHint, visible: !_kept, reserve: true),
        ],
      ),
    );
  }
}

/// The ten codes, read as a list in their order: the first five in the
/// first column, the next five in the second.
class _CodesGrid extends StatelessWidget {
  const _CodesGrid({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final style = codeStyle(context);
    final large = MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
    final narrow = MediaQuery.sizeOf(context).width < FieldSizes.wideBreakpoint;
    Widget code(int i) => Semantics(
      role: SemanticsRole.listItem,
      container: true,
      label: 'Código ${i + 1}: ${spokenRecoveryCode(codes[i])}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Text(codes[i], style: style),
        ),
      ),
    );
    Widget column(Iterable<int> range) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final i in range) code(i)],
    );
    final half = (codes.length / 2).ceil();
    return Semantics(
      role: SemanticsRole.list,
      container: true,
      explicitChildNodes: true,
      child: large && narrow
          ? column(Iterable.generate(codes.length))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: column(Iterable.generate(half))),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: column(
                    Iterable.generate(codes.length - half, (i) => half + i),
                  ),
                ),
              ],
            ),
    );
  }
}

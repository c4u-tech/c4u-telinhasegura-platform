import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'account_write.dart';

/// What the copy holds, in the order of the export document:
/// the account and its linked providers, its sessions (ended ones too),
/// its audit events, then the family as `GET /v1/family` shows the
/// caller, its children and consents, and the children's devices.
const exportContents = [
  'Sua conta e as formas de entrar',
  'Os aparelhos conectados, inclusive os que já saíram',
  'O histórico da conta',
  'A família como você a vê',
  'As crianças e os consentimentos',
  'Os aparelhos das crianças',
];

/// The done state, once the file reached the download or the sheet.
const exportDone = 'Pronto. O arquivo tem seus dados em formato JSON.';

/// The share sheet closed without a choice: nothing was shared, and the
/// copy was not kept.
const exportDismissed =
    'Você fechou sem compartilhar o arquivo. Baixe de novo quando quiser.';

/// `/conta/dados`: what the copy holds, then one action that fetches the
/// export and hands it, as `telinhasegura-dados-YYYY-MM-DD.json`, to the
/// browser's download or the system share sheet.
/// The text lives only in memory,
/// for the length of the handover.
class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  final _action = GlobalKey();
  late final AccountWrite _write;
  bool _started = false;
  bool _done = false;
  bool _dismissed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _write = AccountWrite(
      confirm: () => confirmItsYou(context),
      signOut: AppScope.of(context).client.forgetSession,
    );
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  /// Where the share sheet opens from: the action, which an iPad's
  /// popover points at.
  Rect? get _origin {
    final box = _action.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _download() async {
    final services = AppScope.of(context);
    final origin = _origin;
    setState(() => _dismissed = false);
    var handed = false;
    final ok = await _write.write(() async {
      handed = await services.exports.deliver(
        await services.privacy.export(),
        origin: origin,
      );
    });
    if (!ok || !mounted) return;
    setState(() => handed ? _done = true : _dismissed = true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _write,
    builder: (context, _) => FieldLayout(
      title: 'Seus dados',
      onBack: () => context.go(Routes.account),
      children: _done
          ? [
              const Notice(exportDone),
              const SizedBox(height: Space.xl),
              FilledButton(
                onPressed: () => context.go(Routes.account),
                child: const Text('Voltar para sua conta'),
              ),
            ]
          : _form(),
    ),
  );

  List<Widget> _form() {
    final text = Theme.of(context).textTheme;
    return [
      Text(
        'Uma cópia, em um arquivo, do que o app guarda e mostra para você:',
        style: text.bodyLarge,
      ),
      const SizedBox(height: Space.lg),
      for (final item in exportContents) BulletItem(item),
      const SizedBox(height: Space.sm),
      Text(
        'O arquivo tem a data de hoje no nome e vem em formato JSON.',
        style: text.bodySmall?.copyWith(color: context.palette.muted),
      ),
      const SizedBox(height: Space.xl),
      if (_dismissed) ...[
        const Notice(exportDismissed),
        const SizedBox(height: Space.lg),
      ],
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        key: _action,
        label: 'Baixar meus dados',
        busy: _write.busy,
        onPressed: _write.blocked ? null : _download,
      ),
    ];
  }
}

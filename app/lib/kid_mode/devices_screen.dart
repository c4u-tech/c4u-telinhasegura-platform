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
import '../family/avatars.dart';
import '../family/confirm.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/family_write.dart';
import '../family/widgets.dart';
import '../parental/parental.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'kid_mode_status.dart';

/// The empty list: what a linked device is.
const noDevices =
    'Nenhum aparelho vinculado. Um aparelho vinculado é o celular ou o '
    'tablet da própria criança, ligado à família com um código: ele só '
    'abre o modo criança.';

/// An unlink that found the device already gone (`not_found`).
const deviceGone =
    'Esse aparelho já não estava vinculado. Atualizamos a lista para você.';

/// `/modo-crianca/aparelhos`: the family's linked devices.
/// One row per device with its label, its child and when it was
/// last used, and a quiet "Desvincular" behind a full-screen
/// confirmation; nobody navigates into a row.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final FamilyModel _model;
  late final FamilyWrite _write;
  bool _started = false;
  List<LinkedDevice>? _devices;
  bool _failed = false;

  /// The device an unlink is about, whose row shows the progress.
  String? _pending;

  /// The calm line after an unlink, or after one found the device gone.
  String? _done;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    _write = FamilyWrite(family: _model, confirm: () => confirmItsYou(context));
    scheduleMicrotask(_model.load);
    _read();
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  /// A [quiet] read keeps the list until the answer replaces it.
  Future<void> _read({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _devices = null;
        _failed = false;
      });
    }
    try {
      final devices = await AppScope.of(context).parental.devices();
      if (mounted) setState(() => _devices = devices);
    } on Object catch (e) {
      // no_family ends the family area; the router then leaves.
      if (_model.absorb(e) || !mounted || quiet) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _unlink(LinkedDevice device, String? nickname) async {
    final api = AppScope.of(context).parental;
    final label = device.label;
    final confirmed = await confirmDestructive(
      context,
      title: 'Desvincular $label?',
      body: [
        nickname == null
            ? '$label deixa de ser um aparelho da família.'
            : '$label deixa de ser o aparelho de $nickname.',
        'Ele sai do modo criança na próxima vez que for usado. Para usar '
            'de novo, gere outro código e vincule o aparelho.',
      ],
      action: 'Desvincular',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _pending = device.id;
      _done = null;
    });
    var gone = false;
    final ok = await _write.write(
      () => api.unlink(device.id),
      handle: (ApiError e) => gone = e.code == 'not_found',
    );
    if (ok || gone) await _read(quiet: true);
    if (!mounted) return;
    setState(() {
      _pending = null;
      if (ok) _done = 'Desvinculamos $label.';
      if (gone) _done = deviceGone;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _write]),
    builder: (context, _) => FieldLayout(
      title: 'Aparelhos vinculados',
      onBack: () => context.go(Routes.kidMode),
      children: switch ((_model.state, _devices)) {
        (FamilyReady(:final family), final devices?) => _list(family, devices),
        (FamilyReady(), null) when _failed => [
          const ErrorNote(Copy.genericRetry),
          const SizedBox(height: Space.lg),
          PrimaryButton(label: 'Tentar de novo', onPressed: _read),
        ],
        (FamilyReady(), null) => const [
          FamilyPlaceholder(label: 'Carregando os aparelhos'),
        ],
        _ => familyPending(_model),
      },
    ),
  );

  List<Widget> _list(Family family, List<LinkedDevice> devices) {
    final now = clock.now();
    return [
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ] else if (_done case final done?) ...[
        Notice(done),
        const SizedBox(height: Space.lg),
      ],
      if (devices.isEmpty) ...[
        Text(noDevices, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: Space.xl),
      ] else ...[
        Doors(
          children: [
            for (final device in devices)
              _deviceRow(
                device,
                family.minors.where((m) => m.id == device.minorId).firstOrNull,
                now,
              ),
          ],
        ),
        const SizedBox(height: Space.xl),
      ],
      CapacityRow(
        filled: devices.length,
        total: kMaxDevices,
        words: KidModeWords.capacity(devices.length),
      ),
      if (devices.isEmpty) ...[
        const SizedBox(height: Space.xl),
        PrimaryButton(
          label: 'Vincular o aparelho da criança',
          onPressed: () => context.go(Routes.linkCode),
        ),
      ],
    ];
  }

  Widget _deviceRow(LinkedDevice device, Minor? minor, DateTime now) =>
      _DeviceRow(
        label: device.label,
        avatar: minor?.avatar ?? Avatar.unknown,
        nickname: minor?.nickname,
        lastUsed: KidModeWords.lastUsed(device.lastSeenAt, now),
        busy: _write.busy && _pending == device.id,
        onUnlink: _write.blocked
            ? null
            : () => _unlink(device, minor?.nickname),
      );
}

/// One linked device, in a door row's rhythm but without a chevron:
/// nobody navigates into it. Its label, the child's 40 dp avatar and
/// nickname (a neutral avatar alone when the child is not in the family
/// list), when it was last used, and the quiet clay "Desvincular".
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.label,
    required this.avatar,
    required this.nickname,
    required this.lastUsed,
    required this.busy,
    required this.onUnlink,
  });

  final String label;
  final Avatar avatar;
  final String? nickname;
  final String lastUsed;
  final bool busy;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    final words = [label, if (nickname case final n?) 'de $n', lastUsed];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Padding(
        padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              label: words.join(', '),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    AvatarDisc(avatar),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: text.titleMedium),
                          const SizedBox(height: Space.xs),
                          Text([?nickname, lastUsed].join(' · '), style: muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.xs),
            Padding(
              // Under the text, past the avatar.
              padding: const EdgeInsetsDirectional.only(start: 40 + Space.lg),
              child: QuietAction(
                label: 'Desvincular',
                destructive: true,
                busy: busy,
                onPressed: onUnlink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

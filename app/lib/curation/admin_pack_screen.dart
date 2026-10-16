import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_write.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../catalog/words.dart' show CatalogWords;
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/confirm.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/challenge.dart';
import 'pack.dart';
import 'pack_parts.dart';
import 'pack_words.dart';
import 'role_gate.dart';
import 'words.dart';

/// Back on the list when the pacotinho is gone (`not_found`).
const packGone = 'Esse pacotinho não está mais na curadoria.';

/// Back on the list when a removal finds it already removed
/// (`state_conflict`).
const packAlreadyRemoved = 'Esse pacotinho já tinha sido removido.';

/// Back on the list after "Remover de vez".
String packRemoved(String title) => 'Removemos “$title”.';

/// `/admin/pacotinhos/:id`: the pacotinho's title; where it stands and
/// who composed it, by displayed role; when published, the provenance
/// line ("Revisado por 2 mães ou pais e 1 psicólogo(a) · última revisão
/// ontem"); its videos in order, read; and,
/// while it is not removed, the clay quiet "Remover de vez", confirmed
/// full screen and sent through the re-authentication.
class AdminPackScreen extends StatefulWidget {
  const AdminPackScreen({super.key, required this.id});

  final String id;

  @override
  State<AdminPackScreen> createState() => _AdminPackScreenState();
}

class _AdminPackScreenState extends State<AdminPackScreen> {
  late final ReauthWrite _write;
  bool _started = false;
  bool _failed = false;
  Pack? _pack;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _write = staffWrite(context);
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    scheduleMicrotask(_read);
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final pack = await AppScope.of(context).curation.adminPack(widget.id);
      if (mounted) setState(() => _pack = pack);
    } on Object catch (e) {
      if (!mounted ||
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _read)) {
        return;
      }
      if (e is ApiError && e.code == 'not_found') return _leave(packGone);
      setState(() => _failed = true);
    }
  }

  void _leave(String notice) => context.go(Routes.adminPacks, extra: notice);

  /// Takes the removal's [e]: a lost role goes home; a pacotinho already
  /// removed or gone, back to the list.
  bool _handle(ApiError e) {
    if (takeLostRole(context, e)) return true;
    switch (e.code) {
      case 'state_conflict':
        _leave(packAlreadyRemoved);
      case 'not_found':
        _leave(packGone);
      default:
        return false;
    }
    return true;
  }

  Future<void> _remove(Pack p) async {
    final api = AppScope.of(context).curation;
    final confirmed = await confirmDestructive(
      context,
      title: 'Remover “${p.title}” de vez?',
      body: const [
        'Nenhuma criança vai receber este pacotinho.',
        'Não dá para desfazer.',
      ],
      action: 'Remover de vez',
    );
    if (!confirmed || !mounted) return;
    final ok = await _write.write(() => api.removePack(p.id), handle: _handle);
    if (ok && mounted) _leave(packRemoved(p.title));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _write,
    builder: (context, _) => FieldLayout(
      title: 'Pacotinho',
      onBack: () => context.go(Routes.adminPacks),
      children: _body(),
    ),
  );

  List<Widget> _body() {
    final p = _pack;
    if (p == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando o pacotinho')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    final provenance = p.provenance;
    return [
      Text(p.title, style: text.titleMedium),
      const SizedBox(height: Space.xs),
      Text(
        CurationWords.joined([
          PackWords.state(p),
          'Montado por ${p.composerRole.label}',
        ]),
        style: muted,
      ),
      if (provenance != null) ...[
        const SizedBox(height: Space.md),
        Text(
          CatalogWords.provenance(provenance, clock.now()),
          style: text.bodyLarge,
        ),
      ],
      ..._heading('Vídeos'),
      Doors(
        children: [
          for (final (i, v) in p.videos.indexed)
            PackVideoLine(position: i + 1, video: v),
        ],
      ),
      const SizedBox(height: Space.sm),
      Text(packTotal(p), style: muted),
      if (p.state != PackState.removed) ...[
        const SizedBox(height: Space.xxl),
        if (_write.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.lg),
        ],
        QuietAction(
          label: 'Remover de vez',
          destructive: true,
          busy: _write.busy,
          onPressed: _write.blocked ? null : () => _remove(p),
        ),
      ],
    ];
  }

  List<Widget> _heading(String title) => [
    const SizedBox(height: Space.xl),
    Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
    const SizedBox(height: Space.md),
  ];
}

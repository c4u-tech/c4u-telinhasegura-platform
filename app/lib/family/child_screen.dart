import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'confirm.dart';
import 'family.dart';
import 'family_model.dart';
import 'family_write.dart';
import 'profile_fields.dart';
import 'reconsent_screen.dart' show needsConsent;
import 'widgets.dart';

/// Under "Salvar" while nothing differs from the stored profile.
const unchangedHint = 'Altere um campo para salvar.';

/// `/familia/criancas/:id`: the child's three fields to edit, and
/// "Excluir perfil". Only what changed is
/// sent; an unknown stored avatar or band is shown, never sent back.
class ChildScreen extends StatefulWidget {
  const ChildScreen({super.key, required this.id});

  final String id;

  @override
  State<ChildScreen> createState() => _ChildScreenState();
}

class _ChildScreenState extends State<ChildScreen> {
  final _nickname = TextEditingController();
  late final FamilyModel _model;
  late final FamilyWrite _write;
  bool _started = false;

  /// The stored profile the fields were filled from.
  Minor? _stored;
  Avatar? _avatar;
  AgeBand? _band;

  /// Set once the screen hands back to the list: the child vanishing
  /// from the family is then expected, not news.
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    _write = FamilyWrite(family: _model, confirm: () => confirmItsYou(context));
    scheduleMicrotask(_model.load);
  }

  @override
  void dispose() {
    _nickname.dispose();
    _write.dispose();
    super.dispose();
  }

  void _fill(Minor minor) {
    _stored = minor;
    _nickname.text = minor.nickname;
    _avatar = minor.avatar == Avatar.unknown ? null : minor.avatar;
    _band = minor.ageBand == AgeBand.unknown ? null : minor.ageBand;
  }

  String? get _newNickname {
    final nickname = nicknameOf(_nickname.text);
    return nickname == _stored!.nickname ? null : nickname;
  }

  Avatar? get _newAvatar => _avatar == _stored!.avatar ? null : _avatar;

  AgeBand? get _newBand => _band == _stored!.ageBand ? null : _band;

  /// Something differs, and every field still fits: never an empty patch.
  bool get _changed =>
      nicknameOf(_nickname.text) != null &&
      (_newNickname != null || _newAvatar != null || _newBand != null);

  /// Back to the refreshed list, with [notice] on it.
  Future<void> _toList([String? notice]) async {
    _leaving = true;
    await _model.refresh();
    if (mounted) context.go(Routes.children, extra: notice);
  }

  /// `not_found` from the server: the profile is gone.
  bool _gone(ApiError e) {
    if (e.code != 'not_found') return false;
    unawaited(_toList(Copy.childGone));
    return true;
  }

  Future<void> _save() async {
    final api = AppScope.of(context).family;
    final ok = await _write.write(
      () => api.updateMinor(
        widget.id,
        nickname: _newNickname,
        avatar: _newAvatar,
        ageBand: _newBand,
      ),
      handle: _gone,
    );
    if (ok) await _toList();
  }

  Future<void> _delete() async {
    final api = AppScope.of(context).family;
    final nickname = _stored!.nickname;
    final confirmed = await confirmDestructive(
      context,
      title: 'Excluir perfil',
      body: [
        'O perfil de $nickname será apagado na hora: o apelido, o avatar, '
            'a faixa de idade e o que a criança assistiu, os vídeos e os '
            'totais de tempo de tela.',
        'O consentimento que você deu para o cadastro é retirado. Guardamos '
            'apenas o registro de que você consentiu e quando, sem nenhum '
            'dado da criança.',
      ],
      action: 'Excluir perfil',
    );
    if (!confirmed || !mounted) return;
    final ok = await _write.write(
      () => api.deleteMinor(widget.id),
      handle: _gone,
    );
    if (ok) await _toList();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _write, _nickname]),
    builder: (context, _) {
      final state = _model.state;
      Minor? minor;
      if (state case FamilyReady(:final family)) {
        minor = family.minors.where((m) => m.id == widget.id).firstOrNull;
        if (minor == null && !_leaving) {
          // Opened for a child the family does not hold.
          scheduleMicrotask(() => _toList(Copy.childGone));
          _leaving = true;
        }
      }
      if (minor != null && _stored == null) _fill(minor);
      return FieldLayout(
        title: 'Editar perfil',
        onBack: () => context.go(Routes.children),
        children: switch (_stored) {
          final stored? => _form(stored),
          null => familyPending(_model),
        },
      );
    },
  );

  List<Widget> _form(Minor stored) {
    final title = Theme.of(context).textTheme.titleMedium;
    final idle = !_write.blocked;
    return [
      ChildSummary(
        nickname: stored.nickname,
        avatar: stored.avatar,
        ageBand: stored.ageBand,
      ),
      const SizedBox(height: Space.xl),
      if (!stored.consentCurrent) ...[
        // Kid mode is paused for this child until a guardian authorizes
        // the profile again.
        Doors(
          children: [
            DoorRow(
              title: needsConsent,
              onTap: idle
                  ? () => context.go(Routes.reconsent(widget.id))
                  : null,
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
      ],
      NicknameField(controller: _nickname, enabled: idle),
      const SizedBox(height: Space.xl),
      Text('Avatar', style: title),
      const SizedBox(height: Space.md),
      AvatarPicker(
        value: _avatar,
        onChanged: idle ? (a) => setState(() => _avatar = a) : null,
      ),
      const SizedBox(height: Space.xl),
      Text('Faixa de idade', style: title),
      const SizedBox(height: Space.md),
      AgeBandChoice(
        value: _band,
        adviseUnderTwo: true,
        onChanged: idle ? (b) => setState(() => _band = b) : null,
      ),
      const SizedBox(height: Space.xl),
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Salvar',
        busy: _write.busy,
        onPressed: _changed && idle ? _save : null,
      ),
      SubmitHint(unchangedHint, visible: !_changed),
      const SizedBox(height: Space.xxl),
      QuietAction(
        label: 'Excluir perfil',
        destructive: true,
        onPressed: idle ? _delete : null,
      ),
    ];
  }
}

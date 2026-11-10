import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'consent.dart';
import 'family.dart';
import 'family_model.dart';
import 'family_write.dart';
import 'profile_fields.dart';

/// Under "Continuar" while the profile is incomplete.
const profileHint =
    'Escolha um apelido, um avatar e a faixa de idade para continuar.';

/// `/familia/criancas/nova`: the profile, then the consent over it.
/// Going back a step keeps every value; so
/// does a failed create.
///
/// The same form is the first step of a longer path when given [marks]:
/// both its parts then show them, [onBack] leaves the profile,
/// [onCreated] receives the registered child and [foot] closes each part.
class NewChildScreen extends StatefulWidget {
  const NewChildScreen({
    super.key,
    this.marks,
    this.onBack,
    this.onCreated,
    this.foot = const [],
  });

  /// The longer path's step marks.
  final Widget? marks;
  final VoidCallback? onBack;
  final ValueChanged<Minor>? onCreated;
  final List<Widget> foot;

  @override
  State<NewChildScreen> createState() => _NewChildScreenState();
}

class _NewChildScreenState extends State<NewChildScreen> {
  final _nickname = TextEditingController();
  late final FamilyModel _model;
  late final FamilyWrite _write;
  bool _started = false;
  Avatar? _avatar;
  AgeBand? _band;
  bool _consenting = false;
  bool _agreed = false;

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

  bool get _complete =>
      nicknameOf(_nickname.text) != null && _avatar != null && _band != null;

  Future<void> _create() async {
    final api = AppScope.of(context).family;
    // The consent goes with the version of the text on screen.
    assert(ConsentText.version == kConsentPolicyVersion);
    Minor? created;
    final ok = await _write.write(
      () async => created = await api.createMinor(
        nickname: nicknameOf(_nickname.text)!,
        avatar: _avatar!,
        ageBand: _band!,
      ),
      overrides: const {'limit_reached': Copy.childrenFull},
    );
    if (!ok) return;
    await _model.refresh();
    if (!mounted) return;
    if (widget.onCreated case final onCreated?) {
      onCreated(created!);
    } else {
      context.go(Routes.children);
    }
  }

  /// The marks of [part] (1, the profile; 2, the consent).
  Widget _marks(int part) => widget.marks ?? StepMarks(step: part, of: 2);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_write, _nickname]),
    builder: (context, _) =>
        _consenting ? _consent(context) : _profile(context),
  );

  Widget _profile(BuildContext context) {
    final title = Theme.of(context).textTheme.titleMedium;
    return FieldLayout(
      key: const ValueKey('profile'),
      title: 'Cadastrar criança',
      onBack: widget.onBack ?? () => context.go(Routes.children),
      children: [
        _marks(1),
        const SizedBox(height: Space.xl),
        NicknameField(controller: _nickname),
        const SizedBox(height: Space.xl),
        Text('Avatar', style: title),
        const SizedBox(height: Space.md),
        AvatarPicker(
          value: _avatar,
          onChanged: (a) => setState(() => _avatar = a),
        ),
        const SizedBox(height: Space.xl),
        Text('Faixa de idade', style: title),
        const SizedBox(height: Space.md),
        AgeBandChoice(
          value: _band,
          adviseUnderTwo: true,
          onChanged: (b) => setState(() => _band = b),
        ),
        const SizedBox(height: Space.xl),
        PrimaryButton(
          label: 'Continuar',
          onPressed: _complete
              ? () => setState(() => _consenting = true)
              : null,
        ),
        SubmitHint(profileHint, visible: !_complete),
        ...widget.foot,
      ],
    );
  }

  Widget _consent(BuildContext context) {
    final nickname = nicknameOf(_nickname.text)!;
    return FieldLayout(
      key: const ValueKey('consent'),
      title: 'Consentimento',
      onBack: _write.busy ? null : () => setState(() => _consenting = false),
      children: [
        _marks(2),
        const SizedBox(height: Space.xl),
        // The child the consent is about.
        ChildSummary(nickname: nickname, avatar: _avatar!, ageBand: _band!),
        const SizedBox(height: Space.xl),
        const ConsentTextBlock(title: ConsentText.title),
        const SizedBox(height: Space.md),
        DeclarationRow(
          text: ConsentText.declaration,
          value: _agreed,
          onChanged: _write.busy ? null : (v) => setState(() => _agreed = v),
        ),
        const SizedBox(height: Space.xl),
        if (_write.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.lg),
        ],
        PrimaryButton(
          label: 'Cadastrar',
          busy: _write.busy,
          onPressed: _agreed && !_write.blocked ? _create : null,
        ),
        SubmitHint(declarationHint, visible: !_agreed),
        ...widget.foot,
      ],
    );
  }
}

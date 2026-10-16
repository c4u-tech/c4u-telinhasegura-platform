import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'family.dart';
import 'family_model.dart';
import 'family_write.dart';
import 'labels.dart';
import 'widgets.dart';

const _declaration =
    'Entendo que a família e tudo o que ela guarda são apagados na hora, e '
    'que isso não pode ser desfeito.';

/// `/familia/excluir`, the owner's: the screen is the confirmation. It
/// names what goes (each child by nickname, the pending invitations, the
/// other adults' access), waits for a declaration, then deletes through
/// the re-authentication.
class DeleteFamilyScreen extends StatefulWidget {
  const DeleteFamilyScreen({super.key});

  @override
  State<DeleteFamilyScreen> createState() => _DeleteFamilyScreenState();
}

class _DeleteFamilyScreenState extends State<DeleteFamilyScreen> {
  late final FamilyModel _model;
  late final FamilyWrite _write;
  bool _started = false;
  bool _declared = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    _write = FamilyWrite(
      family: _model,
      confirm: () => confirmItsYou(context),
      ownerOnly: true,
    );
    scheduleMicrotask(_model.load);
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await _write.write(AppScope.of(context).family.delete);
    if (!ok || !mounted) return;
    _model.left();
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _write]),
    builder: (context, _) => FieldLayout(
      title: 'Excluir família',
      onBack: () => context.go(Routes.home),
      children: switch (_model.state) {
        FamilyReady(:final family) => _confirmation(family),
        _ => familyPending(_model),
      },
    ),
  );

  /// What goes, one paragraph per kind, naming only what the family has.
  List<String> _whatGoes(Family family) {
    final nicknames = [for (final minor in family.minors) minor.nickname];
    final others = [
      for (final member in family.members)
        if (member.role != FamilyRole.owner) member.email,
    ];
    final invitations = family.pendingInvitations;
    return [
      'Excluir a família apaga na hora tudo o que ela guarda:',
      if (nicknames.length == 1)
        'O perfil de ${nicknames.single}: o apelido, o avatar e a faixa de '
            'idade. O consentimento dado no cadastro é retirado.'
      else if (nicknames.isNotEmpty)
        'Os perfis de ${FamilyWords.names(nicknames)}: o apelido, o avatar e '
            'a faixa de idade de cada um. Os consentimentos dados nos '
            'cadastros são retirados.',
      if (invitations == 1)
        'O convite esperando resposta, que deixa de valer.'
      else if (invitations > 1)
        'Os ${FamilyWords.invitationsWaiting(invitations)}, que deixam de '
            'valer.',
      if (others.length == 1)
        '${others.single} perde o acesso à família e recebe um e-\u2060mail '
            'avisando.'
      else if (others.isNotEmpty)
        '${FamilyWords.names(others)} perdem o acesso à família e recebem '
            'um e-\u2060mail avisando.',
      'Sua conta continua: depois, você pode começar outra família.',
    ];
  }

  List<Widget> _confirmation(Family family) {
    final body = Theme.of(context).textTheme.bodyLarge;
    final idle = !_write.blocked;
    return [
      for (final paragraph in _whatGoes(family)) ...[
        Text(paragraph, style: body),
        const SizedBox(height: Space.md),
      ],
      const SizedBox(height: Space.md),
      DeclarationRow(
        text: _declaration,
        value: _declared,
        onChanged: idle ? (v) => setState(() => _declared = v) : null,
      ),
      const SizedBox(height: Space.xl),
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Excluir família',
        busy: _write.busy,
        onPressed: _declared && idle ? _delete : null,
      ),
      SubmitHint(declarationHint, visible: !_declared),
    ];
  }
}

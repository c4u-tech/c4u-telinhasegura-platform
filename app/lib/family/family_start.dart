import 'package:flutter/material.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../design/tokens.dart';
import '../shell/services.dart';
import 'family.dart';
import 'inicio.dart' show ChildCard;
import 'labels.dart';
import 'widgets.dart';

const _inviteHelp =
    'O convite chega por e-⁠mail, enviado por quem cuida da família. Abra o '
    'link da mensagem: ele abre o app e mostra a família para você entrar.';

/// The start of a family, for an account that has none yet: what a family
/// is for, the room it has (children and adults, hollow), "Começar minha
/// família" and "Tenho um convite", in the home's module (a child's card),
/// so it stands where the children will. The same on Início and on
/// Família. [onStarted] runs once the family exists; [note] is an error
/// raised elsewhere on the screen (a refused invitation) that this
/// module's own words would otherwise hide.
class FamilyStart extends StatefulWidget {
  const FamilyStart({super.key, required this.onStarted, this.note});

  final VoidCallback onStarted;
  final String? note;

  @override
  State<FamilyStart> createState() => _FamilyStartState();
}

class _FamilyStartState extends State<FamilyStart> {
  final _create = Submission();
  bool _inviteExplained = false;

  @override
  void dispose() {
    _create.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final ok = await _create.run(
      AppScope.of(context).familyModel.create,
      handle: (e) => e.code == 'email_unverified',
    );
    // The family read in its place may already have taken this module
    // away: the screen around it still hears.
    if (ok) widget.onStarted();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _create,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Over the module, as the home sets a failed hand-over over the
        // children.
        if (_create.message ?? widget.note case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.lg),
        ],
        ChildCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Comece a sua família para cadastrar as crianças e chamar '
                  'os outros adultos que cuidam delas.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: Space.lg),
                const CapacityRow(
                  filled: 0,
                  total: kMaxMinors,
                  words: FamilyWords.childrenRoom,
                ),
                const SizedBox(height: Space.md),
                const CapacityRow(
                  filled: 0,
                  total: kMaxAdults,
                  words: FamilyWords.adultsRoom,
                ),
                const SizedBox(height: Space.xl),
                PrimaryButton(
                  label: 'Começar minha família',
                  busy: _create.busy,
                  onPressed: _create.blocked ? null : _start,
                ),
                const SizedBox(height: Space.md),
                OutlinedButton(
                  onPressed: () => setState(() => _inviteExplained = true),
                  child: const Text('Tenho um convite'),
                ),
              ],
            ),
          ),
        ),
        if (_inviteExplained) ...[
          const SizedBox(height: Space.lg),
          const Notice(_inviteHelp),
        ],
      ],
    ),
  );
}

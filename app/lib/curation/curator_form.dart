import 'package:flutter/material.dart';

import '../access/widgets.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/profile_fields.dart' show SelectableRow;
import 'curation.dart';
import 'words.dart';

/// What the admin affirms before a professional role.
const verifiedDeclaration = 'Verifiquei a formação desta pessoa.';

/// Under the primary while no role is chosen.
const chooseRoleHint = 'Escolha o papel acima.';

/// Under the primary while a professional role waits on the affirmation.
const affirmHint = 'Confirme que verificou a formação desta pessoa.';

/// The roles an admin can give, in display order; never [DisplayRole.unknown].
final curatorRoles = [
  for (final r in DisplayRole.values)
    if (r != DisplayRole.unknown) r,
];

/// [heading] ("Papel" by default): the six displayed roles as a choice of one and, only while a
/// professional role is chosen, the declaration that its training was
/// verified. Without [onRole] and
/// [onVerified] (a write running) the choices wait.
class CuratorRoleFields extends StatelessWidget {
  const CuratorRoleFields({
    super.key,
    required this.role,
    required this.verified,
    required this.onRole,
    required this.onVerified,
    this.heading = 'Papel',
    this.subordinate = false,
  });

  final String heading;

  /// Whether [heading] labels the rows under a section's own header (the
  /// member sheet): muted label type, never a header itself, so it never
  /// reads as a peer of the sections.
  final bool subordinate;

  final DisplayRole? role;
  final bool verified;
  final ValueChanged<DisplayRole>? onRole;
  final ValueChanged<bool>? onVerified;

  @override
  Widget build(BuildContext context) {
    final onRole = this.onRole;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subordinate)
          Text(
            heading,
            style: text.labelMedium?.copyWith(color: context.palette.muted),
          )
        else
          Semantics(
            header: true,
            child: Text(heading, style: text.titleMedium),
          ),
        SizedBox(height: subordinate ? Space.sm : Space.md),
        for (final (i, r) in curatorRoles.indexed) ...[
          if (i > 0) const SizedBox(height: Space.sm),
          SelectableRow(
            label: r.label,
            selected: r == role,
            onTap: onRole == null ? null : () => onRole(r),
          ),
        ],
        if (role?.professional ?? false) ...[
          const SizedBox(height: Space.lg),
          DeclarationRow(
            text: verifiedDeclaration,
            value: verified,
            onChanged: onVerified,
          ),
        ],
      ],
    );
  }
}

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../curation/pack_parts.dart' show ReadLine;
import '../curation/words.dart';
import '../design/address.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'account_words.dart';
import 'accounts.dart';

/// One staff action as Auditoria and a sheet's "Ações da equipe" read it,
/// a read line between hairlines
/// and never a door: the event in words in body-large; the
/// subject with how a lookup searched or how many sessions ended; the
/// actor line muted; the reason in quotes on its own line. Addresses
/// show their break marks and are read plain, the whole row as one line.
class AuditActionRow extends StatelessWidget {
  const AuditActionRow(this.action, {super.key});

  final AuditAction action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    final now = clock.now();
    final a = action;
    String about(String Function(String) address) => CurationWords.joined([
      ?AccountWords.subject(a, address: address),
      ...AccountWords.details(a),
    ]);
    final event = AccountWords.event(a.event);
    final subject = about(addressBreaks);
    final actor = AccountWords.actor(a, now, address: addressBreaks);
    final reason = AccountWords.reason(a);
    return ReadLine(
      label: [
        event,
        if (subject.isNotEmpty) about((s) => s),
        AccountWords.actor(a, now),
        ?reason,
      ].join(', '),
      children: [
        Text(event, style: text.bodyLarge),
        if (subject.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Text(subject, style: text.bodyLarge),
        ],
        const SizedBox(height: Space.xs),
        Text(actor, style: muted),
        if (reason != null) ...[
          const SizedBox(height: Space.xs),
          Text(reason, style: text.bodyLarge),
        ],
      ],
    );
  }
}

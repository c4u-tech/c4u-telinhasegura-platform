import 'package:flutter/material.dart';

import '../curation/curation.dart';
import '../design/people_wire.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'words.dart';

/// Who saw a video or a pacotinho before it reached the family: the wire
/// of people, "Visto antes por 3 pessoas" and, beneath, who they were by
/// role and when it was last reviewed. With no approval counted there is
/// no one to draw, so only the last review is said.
class ProvenanceView extends StatelessWidget {
  const ProvenanceView(this.provenance, {super.key, required this.now});

  final Provenance provenance;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lead = CatalogWords.seenBy(provenance);
    final whom = CatalogWords.seenByWhom(provenance, now);
    if (lead == null || whom == null) {
      return Text(
        CatalogWords.provenance(provenance, now),
        style: text.bodyLarge,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PeopleWire(people: CatalogWords.people(provenance)),
        const SizedBox(height: Space.sm),
        Text(lead, style: text.titleMedium),
        const SizedBox(height: Space.xs),
        Text(
          whom,
          style: text.bodyMedium?.copyWith(color: context.palette.muted),
        ),
      ],
    );
  }
}

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../screentime/refetch_on_return.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'curation.dart';
import 'words.dart';

/// What happens to a suggestion, said before anything else.
const suggestionsLead =
    'A curadoria assiste a cada vídeo sugerido antes que qualquer criança '
    'possa ver.';

/// The guardian's empty list.
const noSuggestions = 'Você ainda não sugeriu nenhum vídeo.';

/// `/sugestoes`: what a suggestion goes through, the primary "Sugerir um
/// vídeo", then the guardian's own suggestions, newest first, as read-only
/// rows: title, channel and when, and where each one stands in words.
/// Never who reviewed it, nor how. It reads
/// the list again whenever the guardian comes back from the form.
class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen>
    with RefetchOnReturn {
  bool _started = false;

  /// Null while a read runs with nothing yet to show.
  List<Suggestion>? _mine;
  bool _failed = false;

  @override
  String get ownPath => Routes.suggestions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    watchReturns();
    // Beneath the form opened directly, it reads once shown.
    if (isHere) _read();
  }

  @override
  void onReturn() => _read();

  Future<void> _read() async {
    setState(() => _failed = false);
    try {
      final mine = await AppScope.of(context).curation.suggestions();
      mine.sort((a, b) => b.suggestedAt.compareTo(a.suggestedAt));
      if (mounted) setState(() => _mine = mine);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FieldLayout(
      title: 'Sugestões',
      onBack: () => context.go(Routes.home),
      children: [
        Text(suggestionsLead, style: text.bodyLarge),
        const SizedBox(height: Space.xl),
        PrimaryButton(
          label: 'Sugerir um vídeo',
          onPressed: () => context.go(Routes.newSuggestion),
        ),
        const SizedBox(height: Space.xxl),
        Semantics(
          header: true,
          child: Text('Suas sugestões', style: text.titleMedium),
        ),
        const SizedBox(height: Space.md),
        ..._list(text),
      ],
    );
  }

  List<Widget> _list(TextTheme text) {
    final mine = _mine;
    // A failed read keeps the screen's one primary: the retry is quiet.
    if (_failed) {
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.sm),
        QuietAction(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    if (mine == null) {
      return const [FamilyPlaceholder(label: 'Carregando suas sugestões')];
    }
    if (mine.isEmpty) return [Text(noSuggestions, style: text.bodyLarge)];
    final now = clock.now();
    return [
      Doors(children: [for (final s in mine) _SuggestionRow(s, now)]),
    ];
  }
}

/// One suggestion, read and never a target: its title in body-large up
/// to two lines, "Canal · há 3 dias" muted, then where it stands.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow(this.suggestion, this.now);

  final Suggestion suggestion;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = suggestion;
    final when = CurationWords.ago(s.suggestedAt, now);
    final state = s.state.label;
    return Semantics(
      container: true,
      label: [s.title, s.channelTitle, when, state].join(', '),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: text.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  CurationWords.joined([s.channelTitle, when]),
                  style: text.bodyMedium?.copyWith(
                    color: context.palette.muted,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(state, style: text.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

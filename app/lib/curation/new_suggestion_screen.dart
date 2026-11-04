import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'curation.dart';
import 'search_result.dart';
import 'search_results.dart';
import 'shared_link.dart';
import 'suggestion_confirmation.dart';
import 'suggestion_words.dart';
import 'words.dart';

/// `/sugestoes/nova`: one field that takes either a YouTube link or words
/// from a title. A link is sent once, then the done state says whether the
/// suggestion created the video or found it already with the curators.
/// Words search YouTube, on request only, and list what came back; a hit
/// is confirmed on its own screen before it is sent. Searching and sending
/// fail apart: a search's limit or outage never stops a link. A refused
/// video or a link that is no video is worded on the field; a rate limit
/// counts down; anything else is the error note, and the primary tries
/// again.
class NewSuggestionScreen extends StatefulWidget {
  const NewSuggestionScreen({super.key, this.initialLink});

  /// A link that arrived by sharing: it fills the field, and nothing is
  /// sent until the guardian taps the primary.
  final String? initialLink;

  @override
  State<NewSuggestionScreen> createState() => _NewSuggestionScreenState();
}

class _NewSuggestionScreenState extends State<NewSuggestionScreen> {
  final _field = TextEditingController();
  final _send = Submission();
  final _search = Submission();
  final _thumbs = <String, Future<Uint8List>>{};
  late String _lastText;
  String? _fieldError;

  /// Why the last search failed, when the server said YouTube's search is
  /// out: for the day ([searchDaily]) or for now ([searchNow]).
  String? _unavailable;

  /// The last search's results, kept while the words change until the next
  /// search; null before any.
  List<SearchResult>? _results;

  /// Whether "Colar link" just found no link.
  bool _nothingToPaste = false;

  /// Set once sent: whether this suggestion created the video.
  bool? _created;

  @override
  void initState() {
    super.initState();
    // Before the listener, so the prefill clears nothing.
    _field.text = widget.initialLink ?? '';
    _lastText = _field.text;
    _field.addListener(_edited);
  }

  @override
  void dispose() {
    _field.dispose();
    _send.dispose();
    _search.dispose();
    super.dispose();
  }

  /// New words take back what was said about the old ones; moving the
  /// cursor does not.
  void _edited() {
    if (_field.text == _lastText) return;
    _lastText = _field.text;
    _send.clearMessage();
    _search.clearMessage();
    setState(() {
      _fieldError = null;
      _unavailable = null;
      _nothingToPaste = false;
    });
  }

  String get _text => _field.text.trim();

  /// The YouTube link the field holds, if it holds one.
  String? get _link => youtubeLinkIn(_text);

  /// The words' length as a search counts it: inner spaces collapsed.
  int get _length => _text.split(RegExp(r'\s+')).join(' ').runes.length;

  bool get _searchable => _length >= searchMin && _length <= searchMax;

  /// A hit's thumbnail, read once and shared by its row and its
  /// confirmation; one that failed is forgotten, so the next place it
  /// shows asks again.
  Future<Uint8List> _thumb(String youtubeId) =>
      _thumbs.putIfAbsent(youtubeId, () {
        final bytes = AppScope.of(context).curation.searchThumbnail(youtubeId);
        bytes.then(
          (_) {},
          onError: (Object _) {
            _thumbs.remove(youtubeId);
          },
        );
        return bytes;
      });

  Future<void> _sendLink() async {
    final url = _link;
    if (url == null) return;
    final api = AppScope.of(context).curation;
    late bool created;
    final ok = await _send.run(
      () async => created = (await api.suggest(url)).created,
      overrides: const {'video_source_unavailable': sourceUnavailable},
      handle: _onField,
    );
    if (ok && mounted) setState(() => _created = created);
  }

  /// A refusal or a link that is no video belongs to the field.
  bool _onField(ApiError e) {
    final words = switch (e.code) {
      'video_refused' => e.refusal!.message,
      'invalid_link' || 'validation' => invalidLink,
      _ => null,
    };
    if (words == null) return false;
    setState(() => _fieldError = words);
    return true;
  }

  Future<void> _runSearch() async {
    if (!_searchable) return;
    final q = _text;
    final api = AppScope.of(context).curation;
    final view = View.of(context);
    setState(() {
      _unavailable = null;
      _results = null;
    });
    late List<SearchResult> found;
    final ok = await _search.run(
      () async => found = await api.search(q),
      handle: _onSearchOut,
    );
    if (!ok || !mounted) return;
    setState(() => _results = found);
    unawaited(
      SemanticsService.sendAnnouncement(
        view,
        found.isEmpty ? noResults : foundWords(found.length),
        TextDirection.ltr,
      ),
    );
  }

  /// YouTube's search being out is worded by whether it waits for the
  /// next day.
  bool _onSearchOut(ApiError e) {
    if (e.code != 'search_unavailable') return false;
    setState(
      () => _unavailable = e.retryAfter != null ? searchDaily : searchNow,
    );
    return true;
  }

  Future<void> _paste() async {
    String? held;
    try {
      held = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Object {
      held = null;
    }
    if (!mounted) return;
    final found = youtubeLinkIn(held);
    if (found == null) {
      setState(() => _nothingToPaste = true);
      return;
    }
    _field.value = TextEditingValue(
      text: found,
      selection: TextSelection.collapsed(offset: found.length),
    );
  }

  Future<void> _pick(SearchResult result) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SuggestionConfirmation(
          result: result,
          thumbnail: _thumb,
          send: _send,
        ),
      ),
    );
    if (created != null && mounted) setState(() => _created = created);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_send, _search]),
    builder: (context, _) => FieldLayout(
      title: 'Sugerir um vídeo',
      onBack: () => context.go(Routes.suggestions),
      children: switch (_created) {
        final created? => [
          Notice(
            created
                ? 'Recebemos sua sugestão.'
                : 'Esse vídeo já está com a curadoria.',
          ),
          const SizedBox(height: Space.xl),
          PrimaryButton(
            label: 'Voltar para sugestões',
            onPressed: () => context.go(Routes.suggestions),
          ),
        ],
        null => _form(),
      },
    ),
  );

  /// What the primary and the keyboard's action do for the words in the
  /// field now: send a link, search, or nothing yet.
  VoidCallback? get _action => _link != null
      ? (_send.blocked ? null : _sendLink)
      : (_searchable && !_search.blocked ? _runSearch : null);

  List<Widget> _form() {
    final isLink = _link != null;
    final work = isLink ? _send : _search;
    // A failed request's note stands until the words change: the primary
    // is then its retry. A countdown waits instead.
    final note = isLink ? _send.message : _search.message ?? _unavailable;
    final retry =
        (work.message != null && !work.blocked) ||
        (!isLink && _unavailable == searchNow);
    final hint = switch (_length) {
      _ when isLink => null,
      0 => emptyHint,
      < searchMin => shortHint,
      > searchMax => longHint,
      _ => null,
    };
    final action = _action;
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted);
    final results = _results;
    return [
      _fieldWithPaste(isLink: isLink),
      if (_nothingToPaste) ...[
        const SizedBox(height: Space.sm),
        Semantics(liveRegion: true, child: Text(noClipboardLink, style: muted)),
      ],
      const SizedBox(height: Space.xl),
      if (note != null) ...[ErrorNote(note), const SizedBox(height: Space.lg)],
      PrimaryButton(
        label: retry
            ? 'Tentar de novo'
            : isLink
            ? 'Enviar sugestão'
            : 'Buscar',
        busy: work.busy,
        onPressed: action,
      ),
      // Under results the hint gives back its space, so more of them show.
      SubmitHint(
        hint ?? emptyHint,
        visible: hint != null,
        reserve: results == null && !_search.busy,
      ),
      if (_search.busy) ...[
        const SizedBox(height: Space.xl),
        const FamilyPlaceholder(label: 'Buscando no YouTube'),
      ] else if (results != null) ...[
        const SizedBox(height: Space.xl),
        SearchResults(results: results, thumbnail: _thumb, onPick: _pick),
      ],
    ];
  }

  /// The field and, beside it (under it at large text), the quiet "Colar
  /// link", which reads the clipboard only when tapped.
  Widget _fieldWithPaste({required bool isLink}) {
    final under = largeText(context);
    final input = TextField(
      controller: _field,
      keyboardType: TextInputType.text,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: isLink ? TextInputAction.send : TextInputAction.search,
      // At large text the words wrap rather than scroll out of sight; the
      // keyboard's action still searches or sends.
      minLines: 1,
      maxLines: under ? null : 1,
      onSubmitted: (_) => _action?.call(),
      decoration: InputDecoration(
        // Always above the field, so it never shortens to fit inside; at
        // large text it stands on its own line over the field instead.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        label: under ? null : const Text(fieldLabel),
        errorText: _fieldError,
        errorMaxLines: 4,
      ),
    );
    final paste = QuietAction(
      label: 'Colar link',
      onPressed: _paste,
      inline: !under,
    );
    if (under) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Merged, the label is read once, as the field's own.
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  fieldLabel,
                  style: Theme.of(context)
                      .inputDecorationTheme
                      .floatingLabelStyle,
                ),
                const SizedBox(height: Space.sm),
                input,
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          paste,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: input),
        const SizedBox(width: Space.sm),
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: paste,
        ),
      ],
    );
  }
}

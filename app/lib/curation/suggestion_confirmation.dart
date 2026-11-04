import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../kid/shelves.dart' show ThumbnailLoader;
import '../shell/services.dart';
import 'curation.dart';
import 'search_result.dart';
import 'suggestion_words.dart';
import 'video_heading.dart';
import 'words.dart';

/// The link a search hit is suggested by: YouTube's own watch page.
String watchLink(String youtubeId) =>
    Uri.https('www.youtube.com', '/watch', {'v': youtubeId}).toString();

/// A search hit seen large before it is sent: a whole task screen over the
/// results, so going back finds them as they were. It closes with whether
/// the suggestion created the video once sent, or with nothing when the
/// guardian goes back. A video refused since the search says why here,
/// leaving only the way back.
class SuggestionConfirmation extends StatefulWidget {
  const SuggestionConfirmation({
    super.key,
    required this.result,
    required this.thumbnail,
    required this.send,
  });

  final SearchResult result;
  final ThumbnailLoader thumbnail;

  /// The screen's sending, shared so a rate limit counts down for every
  /// way of sending.
  final Submission send;

  @override
  State<SuggestionConfirmation> createState() => _SuggestionConfirmationState();
}

class _SuggestionConfirmationState extends State<SuggestionConfirmation> {
  late final Future<Uint8List> _picture = widget.thumbnail(
    widget.result.youtubeId,
  );

  /// Why the video can no longer be suggested, once the server says so.
  String? _refusal;

  Future<void> _submit() async {
    final api = AppScope.of(context).curation;
    late bool created;
    final ok = await widget.send.run(
      () async =>
          created = (await api.suggest(watchLink(widget.result.youtubeId)))
              .created,
      overrides: const {'video_source_unavailable': sourceUnavailable},
      handle: _onRefusal,
    );
    if (ok && mounted) Navigator.of(context).pop(created);
  }

  bool _onRefusal(ApiError e) {
    final words = switch (e.code) {
      'video_refused' => e.refusal!.message,
      'invalid_link' || 'validation' => invalidLink,
      _ => null,
    };
    if (words == null) return false;
    setState(() => _refusal = words);
    return true;
  }

  void _back() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final send = widget.send;
    return ListenableBuilder(
      listenable: send,
      builder: (context, _) => FieldLayout(
        title: 'Sugerir este vídeo?',
        onBack: _back,
        children: [
          _Picture(_picture),
          const SizedBox(height: Space.lg),
          VideoHeading.parts(
            title: r.title,
            channelTitle: r.channelTitle,
            duration: Duration(seconds: r.durationSeconds),
          ),
          const SizedBox(height: Space.xl),
          if (_refusal ?? send.message case final note?) ...[
            ErrorNote(note),
            const SizedBox(height: Space.lg),
          ],
          // A failed send's note stands, and the primary is its retry; a
          // countdown waits instead.
          if (_refusal == null)
            PrimaryButton(
              label: send.message != null && !send.blocked
                  ? 'Tentar de novo'
                  : 'Enviar sugestão',
              busy: send.busy,
              onPressed: send.blocked ? null : _submit,
            ),
          const SizedBox(height: Space.xxl),
          QuietAction(label: 'Voltar aos resultados', onPressed: _back),
        ],
      ),
    );
  }
}

/// The thumbnail at the column's width, 16:9 and square-edged, nothing of
/// ours over it; while it loads, or if it never comes, its edge alone.
class _Picture extends StatelessWidget {
  const _Picture(this.bytes);

  final Future<Uint8List> bytes;

  @override
  Widget build(BuildContext context) {
    final edge = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.palette.outline, width: 1.5),
      ),
    );
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: FutureBuilder(
        future: bytes,
        builder: (context, snap) => switch (snap) {
          AsyncSnapshot(hasData: true, :final data!) => Image.memory(
            data,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => edge,
          ),
          _ => edge,
        },
      ),
    );
  }
}

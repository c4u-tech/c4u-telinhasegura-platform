import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'curation.dart';
import 'words.dart';

/// Under the primary while the field is empty (disabled with
/// a hint).
const linkHint = 'Cole acima o link de um vídeo do YouTube.';

/// `invalid_link` (and `validation`), on the field.
const invalidLink = 'Esse link não é de um vídeo do YouTube.';

/// `video_source_unavailable`: YouTube did not answer the server.
const sourceUnavailable =
    'Não conseguimos consultar o YouTube agora. Tente de novo em alguns '
    'minutos.';

/// `/sugestoes/nova`: one YouTube link, sent once, then the done state
/// saying whether the suggestion created the video or found it already
/// with the curators. A refused video or a
/// link that is no video is worded on the field; a rate limit counts
/// down; anything else is the error note, and the primary tries again.
class NewSuggestionScreen extends StatefulWidget {
  const NewSuggestionScreen({super.key});

  @override
  State<NewSuggestionScreen> createState() => _NewSuggestionScreenState();
}

class _NewSuggestionScreenState extends State<NewSuggestionScreen> {
  final _link = TextEditingController();
  final _send = Submission();
  String? _fieldError;

  /// Set once sent: whether this suggestion created the video.
  bool? _created;

  @override
  void initState() {
    super.initState();
    _link.addListener(() {
      _send.clearMessage();
      setState(() => _fieldError = null);
    });
  }

  @override
  void dispose() {
    _link.dispose();
    _send.dispose();
    super.dispose();
  }

  String get _url => _link.text.trim();

  Future<void> _submit() async {
    final url = _url;
    if (url.isEmpty) return;
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _send,
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

  List<Widget> _form() {
    final empty = _url.isEmpty;
    // A failed send's note stands until the link changes: the primary is
    // then its retry. A countdown waits instead.
    final retry = _send.message != null && !_send.blocked;
    return [
      TextField(
        controller: _link,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) {
          if (!_send.blocked) _submit();
        },
        decoration: InputDecoration(
          labelText: 'Link do YouTube',
          errorText: _fieldError,
          errorMaxLines: 4,
        ),
      ),
      const SizedBox(height: Space.xl),
      if (_send.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: retry ? 'Tentar de novo' : 'Enviar sugestão',
        busy: _send.busy,
        onPressed: empty || _send.blocked ? null : _submit,
      ),
      SubmitHint(linkHint, visible: empty, reserve: true),
    ];
  }
}

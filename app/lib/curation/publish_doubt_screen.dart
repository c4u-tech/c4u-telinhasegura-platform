import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_write.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../family/family.dart';
import '../family/profile_fields.dart' show AgeBandChoice, SelectableRow;
import '../family/widgets.dart' show FamilyPlaceholder;
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/challenge.dart';
import 'curation.dart';
import 'held_video_screen.dart' show heldGone;
import 'role_gate.dart';
import 'video_heading.dart';
import 'words.dart';

const publishLead =
    'Publicar põe o vídeo nas prateleiras com o tema e a idade que você '
    'escolher. O motivo fica registrado.';
const publishHint = 'Escolha um tema e uma idade e escreva o motivo.';
const publishReasonInvalid = 'Escreva um motivo de 3 a 200 caracteres.';

/// Back on the list after "Publicar".
String publishedFromDoubt(String title) =>
    'Publicamos “$title”. A dúvida da curadoria ficou decidida.';

/// `/moderacao/retidos/:id/publicar`: a moderator or an admin settles a
/// curator's doubt by publishing: one theme of six, a band of three and a
/// reason of 3 to 200 characters, through [ReauthWrite]. A video no
/// longer held by a doubt goes back to the list.
class PublishDoubtScreen extends StatefulWidget {
  const PublishDoubtScreen({super.key, required this.id, this.held});

  final String id;

  /// The held video as its screen read it; opened directly, it is read.
  final HeldVideo? held;

  @override
  State<PublishDoubtScreen> createState() => _PublishDoubtScreenState();
}

class _PublishDoubtScreenState extends State<PublishDoubtScreen> {
  late final ReauthWrite _write;
  final _reason = TextEditingController();
  bool _started = false;
  HeldVideo? _held;
  bool _failed = false;
  VideoTheme? _theme;
  AgeBand? _band;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    _reason.addListener(() {
      _write.clearMessage();
      setState(() => _fieldError = null);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _write = staffWrite(context);
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    _held = widget.held;
    if (_held == null) scheduleMicrotask(_read);
  }

  @override
  void dispose() {
    _write.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final all = await AppScope.of(context).staff.heldVideos();
      if (!mounted) return;
      final held = all.where((h) => h.video.id == widget.id).firstOrNull;
      if (held == null || held.heldReason != HeldReason.doubt) {
        return context.go(Routes.heldVideos, extra: heldGone);
      }
      setState(() => _held = held);
    } on Object catch (e) {
      if (!mounted ||
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _read)) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  bool _handle(ApiError e) {
    if (takeLostRole(context, e)) return true;
    if (e.code == 'state_conflict' || e.code == 'not_found') {
      context.go(Routes.heldVideos, extra: heldGone);
      return true;
    }
    if (e.code != 'reason_required') return false;
    setState(() => _fieldError = publishReasonInvalid);
    return true;
  }

  Future<void> _publish(Video v, VideoTheme theme, AgeBand band) async {
    final api = AppScope.of(context).staff;
    final ok = await _write.write(
      () => api.decideDoubt(
        v.id,
        publish: true,
        theme: theme,
        minAgeBand: band,
        reason: _reason.text.trim(),
      ),
      handle: _handle,
    );
    if (ok && mounted) {
      context.go(Routes.heldVideos, extra: publishedFromDoubt(v.title));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _write,
    builder: (context, _) => FieldLayout(
      title: 'Publicar',
      onBack: () => context.go(Routes.heldVideo(widget.id)),
      children: _body(),
    ),
  );

  List<Widget> _body() {
    final held = _held;
    if (held == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando o vídeo')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    final text = Theme.of(context).textTheme;
    final idle = !_write.blocked;
    final theme = _theme;
    final band = _band;
    final ready =
        theme != null && band != null && _reason.text.trim().isNotEmpty;
    return [
      VideoHeading(held.video),
      const SizedBox(height: Space.xl),
      Text(publishLead, style: text.bodyLarge),
      const SizedBox(height: Space.xl),
      Text('Tema', style: text.titleMedium),
      const SizedBox(height: Space.md),
      for (final (i, t) in VideoTheme.values.indexed)
        if (t != VideoTheme.unknown) ...[
          if (i > 0) const SizedBox(height: Space.sm),
          SelectableRow(
            label: t.label,
            selected: t == theme,
            onTap: idle ? () => setState(() => _theme = t) : null,
          ),
        ],
      const SizedBox(height: Space.xl),
      Text('A partir de', style: text.titleMedium),
      const SizedBox(height: Space.md),
      AgeBandChoice(
        value: band,
        onChanged: idle ? (b) => setState(() => _band = b) : null,
      ),
      const SizedBox(height: Space.xl),
      TextField(
        controller: _reason,
        maxLength: 200,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Motivo',
          errorText: _fieldError,
          errorMaxLines: 3,
        ),
      ),
      const SizedBox(height: Space.xl),
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Publicar',
        busy: _write.busy,
        onPressed: ready && idle
            ? () => _publish(held.video, theme, band)
            : null,
      ),
      SubmitHint(publishHint, visible: !ready, reserve: true),
    ];
  }
}

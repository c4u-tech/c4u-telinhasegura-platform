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
import 'approve_screen.dart' show tooLongForYoungestLine;
import 'band_answer_row.dart';
import 'curation.dart';
import 'held_video_screen.dart' show doubtsHeading, heldGone;
import 'role_gate.dart';
import 'video_heading.dart';
import 'words.dart';

const publishLead =
    'Publicar põe o vídeo no app com o tema e a idade que você escolher. '
    'O motivo fica registrado.';
const publishHint = 'Escolha um tema e uma idade e escreva o motivo.';
const publishReasonInvalid = 'Escreva um motivo de 3 a 200 caracteres.';

/// The band the round's answers give, stated over the answers behind it.
String roundBandStatement(AgeBand from) =>
    'Pelas respostas da rodada, este vídeo serve a partir de ${from.label}';

/// Who gave an answer, by displayed role: "Mãe ou pai respondeu".
String answeredBy(DisplayRole role) => '${role.label} respondeu';

/// `not_watched` here: the player is on the held video's screen, a step
/// back.
const publishNotWatched =
    'Para publicar, o vídeo precisa tocar até o fim. Volte, assista até o '
    'fim e publique de novo.';

/// Back on the list after "Publicar".
String publishedFromDoubt(String title) =>
    'Publicamos “$title”. A dúvida da curadoria ficou decidida.';

/// `/moderacao/retidos/:id/publicar`: a moderator or an admin settles a
/// curator's doubt by publishing: one theme of six, a band of three and a
/// reason of 3 to 200 characters, through [ReauthWrite]. Above the theme
/// and band, the band the round's answers give, stated, with each answer
/// behind it and who gave it by displayed role, never to be changed here.
/// A video no longer held by a doubt goes back to the list. The bands younger than
/// the round's answers allow are not offered, nor "2 a 4 anos" for a video
/// longer than the youngest band allows; the server holds the rule, so a
/// band it refuses goes away with every younger one.
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

  /// The band the server last refused for this video, if any.
  AgeBand? _refused;

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
    if (widget.held case final held?) {
      _take(held);
    } else {
      scheduleMicrotask(_read);
    }
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
      setState(() => _take(held));
    } on Object catch (e) {
      if (!mounted ||
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _read)) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  /// The held video, and the theme and band a doubting curator chose as
  /// the starting choice: the moderator confirms or changes them.
  void _take(HeldVideo held) {
    _held = held;
    _theme ??= held.doubts
        .map((d) => d.theme)
        .where((t) => t != null && t != VideoTheme.unknown)
        .firstOrNull;
    _band ??= held.doubts
        .map((d) => d.minAgeBand)
        .where((b) => b != null && b != AgeBand.unknown)
        .firstOrNull;
    if (_barred(held).contains(_band)) _band = null;
  }

  static bool _tooLong(HeldVideo held) =>
      held.video.duration > defaultYoungestMax;

  /// The youngest band the round's answers allow, as the server computed
  /// it; null when it does not say.
  static AgeBand? _computed(HeldVideo held) => switch (held.computedBand) {
    final b? when b != AgeBand.unknown => b,
    _ => null,
  };

  /// The bands not offered: those younger than the round's answers allow,
  /// "2 a 4 anos" for a video too long for it, and the band the server
  /// refused with every younger one.
  Set<AgeBand> _barred(HeldVideo held) {
    final from = _computed(held);
    return {
      for (final b in AgeBand.values)
        if (b != AgeBand.unknown &&
            (from != null && b.index < from.index ||
                b == AgeBand.upTo4 && _tooLong(held) ||
                _refused != null && b.index <= _refused!.index))
          b,
    };
  }

  bool _handle(ApiError e) {
    if (takeLostRole(context, e)) return true;
    if (e.code == 'state_conflict' || e.code == 'not_found') {
      context.go(Routes.heldVideos, extra: heldGone);
      return true;
    }
    if (e.code == 'checklist_band') {
      setState(() {
        _refused = _band;
        _band = null;
      });
      return false;
    }
    if (e.code != 'reason_required') return false;
    setState(() => _fieldError = publishReasonInvalid);
    return true;
  }

  /// An end report the held screen failed to send is sent once more
  /// first, since the server refuses a publication it never heard the end
  /// of.
  Future<void> _publish(Video v, VideoTheme theme, AgeBand band) async {
    final scope = AppScope.of(context);
    final api = scope.staff;
    final ends = scope.moderatorEnds;
    final ok = await _write.write(
      () async {
        await ends.resend(v.id);
        await api.decideDoubt(
          v.id,
          publish: true,
          theme: theme,
          minAgeBand: band,
          reason: _reason.text.trim(),
        );
      },
      overrides: const {'not_watched': publishNotWatched},
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
      if (held.doubts.isNotEmpty) ...[
        const SizedBox(height: Space.xl),
        Semantics(
          header: true,
          child: Text(doubtsHeading, style: text.titleMedium),
        ),
        const SizedBox(height: Space.sm),
        for (final d in held.doubts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Text(CurationWords.review(d), style: text.bodyLarge),
          ),
      ],
      if (_computed(held) case final from?) ...[
        const SizedBox(height: Space.xl),
        Semantics(
          header: true,
          child: Text(roundBandStatement(from), style: text.headlineSmall),
        ),
        const SizedBox(height: Space.xs),
        for (final b in held.bandAnswers)
          BandAnswerRow(
            question: b.text,
            word: b.answer.word,
            changeable: false,
            by: answeredBy(b.displayRole),
          ),
      ],
      // The length, not an answer, bars the youngest band.
      if (_tooLong(held) && held.bandAnswers.isEmpty) ...[
        const SizedBox(height: Space.sm),
        Text(tooLongForYoungestLine, style: text.bodyLarge),
      ],
      const SizedBox(height: Space.xl),
      Text('Tema', style: text.titleMedium),
      const SizedBox(height: Space.md),
      for (final (i, t) in VideoTheme.values.indexed)
        if (t != VideoTheme.unknown) ...[
          if (i > 0) const SizedBox(height: Space.sm),
          SelectableRow(
            // Read with its meaning, as it is shown.
            label: '${t.label}, ${t.definition}',
            text: t.label,
            detail: t.definition,
            selected: t == theme,
            onTap: idle ? () => setState(() => _theme = t) : null,
          ),
        ],
      const SizedBox(height: Space.xl),
      Text('A partir de', style: text.titleMedium),
      const SizedBox(height: Space.md),
      AgeBandChoice(
        value: band,
        disabled: _barred(held),
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

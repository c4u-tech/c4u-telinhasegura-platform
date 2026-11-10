import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../catalog/pack_rows.dart';
import '../catalog/video_row.dart';
import '../catalog/words.dart';
import '../curation/family_catalog.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../screentime/refetch_on_return.dart';
import '../screentime/screentime_api.dart';
import '../screentime/today.dart';
import '../screentime/words.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'avatars.dart';
import 'confirm.dart';
import 'family.dart';
import 'family_model.dart';
import 'family_write.dart';
import 'labels.dart';
import 'reconsent_screen.dart' show needsConsent;
import 'widgets.dart';

/// From a screen about a child the family no longer holds (`not_found`,
/// or absent from the family): back to the refreshed children with a
/// notice.
Future<void> leaveForGoneChild(BuildContext context, FamilyModel model) async {
  await model.refresh();
  if (context.mounted) context.go(Routes.children, extra: Copy.childGone);
}

/// A section's title on a page of sections: title-medium, marked as a
/// header, so the sections read as peers under the page's one display
/// title.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// The muted label naming a group of rows inside a section, never a
/// header, so it never reads as a peer of the sections.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.words);

  final String words;

  @override
  Widget build(BuildContext context) => Text(
    words,
    style: Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: context.palette.muted),
  );
}

/// `/familia/criancas/:id`: everything a guardian does for one child, on
/// one scrolling page, today first. Under the avatar, the nickname and the
/// age band: "Hoje" (the day's modules and words, "Mais tempo hoje",
/// "Limite e horário", the six days before), "Vídeos" (today's
/// pacotinhos, the first videos with a quiet "Esconder" each, the way to
/// all of them) and "Perfil" (the profile with "Editar", and "Excluir
/// perfil" at the foot).
///
/// [path] is where the page stands: it also stands beneath the
/// screen-time errands, whose own paths it keeps. [back] is where its back
/// control goes; [notice] a calm line brought back from a video or a
/// pacotinho that left the catalogue.
class ChildPage extends StatefulWidget {
  const ChildPage({
    super.key,
    required this.id,
    this.path,
    this.back = Routes.children,
    this.notice,
  });

  final String id;

  /// Where the page stands, when not at its own path.
  final String? path;
  final String back;
  final String? notice;

  /// Opening the page from the home hands it this, so back returns there.
  static const fromHome = #fromHome;

  /// How many videos the page lists before "Ver todos os vídeos".
  static const firstVideos = 3;

  static const todayKey = Key('child-page-today');
  static const videosKey = Key('child-page-videos');
  static const profileKey = Key('child-page-profile');

  @override
  State<ChildPage> createState() => _ChildPageState();
}

/// A video's slot once the guardian hid it from the page: the notice
/// with "Desfazer", or, when it left the catalogue, the notice alone.
enum _Slot { hidden, gone }

class _ChildPageState extends State<ChildPage> with RefetchOnReturn {
  final _reading = Submission();
  final _hiding = Submission();

  /// "Desfazer" of the video just hidden, which takes the focus the
  /// hidden row's "Esconder" had.
  final _undoFocus = FocusNode(debugLabel: 'desfazer');
  late final FamilyModel _model;
  late final FamilyWrite _delete;
  bool _started = false;

  /// Set once the page hands back to the children.
  bool _leaving = false;

  Future<ScreenTimeRules>? _rules;
  Future<List<DayUsage>>? _week;

  List<FamilyVideo>? _videos;
  List<FamilyPack> _packs = const [];
  bool _hasMore = false;

  /// The first catalogue read failed: "Tentar de novo" stays.
  bool _videosFailed = false;

  /// The videos hidden from this page, each holding its slot.
  final _slots = <String, _Slot>{};

  /// The video the last hide or undo wrote, where its outcome stands.
  String? _writing;

  String? _notice;

  @override
  String get ownPath => widget.path ?? Routes.child(widget.id);

  @override
  void initState() {
    super.initState();
    _notice = widget.notice;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    _delete = FamilyWrite(
      family: _model,
      confirm: () => confirmItsYou(context),
    );
    watchReturns();
    scheduleMicrotask(_model.load);
    // Beneath an errand opened directly, it reads once shown.
    if (isHere) _readAll();
  }

  @override
  void dispose() {
    _reading.dispose();
    _hiding.dispose();
    _undoFocus.dispose();
    _delete.dispose();
    super.dispose();
  }

  @override
  void onReturn() => _readAll();

  void _readAll() {
    _readDay();
    unawaited(_readVideos());
  }

  void _readDay() {
    final api = AppScope.of(context).screenTime;
    final rules = api.rules(widget.id);
    final week = api.usage(widget.id).then((days) => days.reversed.toList());
    for (final read in [rules, week]) {
      unawaited(read.then<void>((_) {}, onError: _readFailed));
    }
    setState(() {
      _rules = rules;
      _week = week;
    });
  }

  void _readFailed(Object error) {
    if (error is ApiError) _gone(error);
  }

  Future<void> _readVideos() async {
    final api = AppScope.of(context).familyCatalog;
    final ok = await _reading.run(() async {
      final page = await api.minorCatalog(widget.id);
      if (!mounted) return;
      setState(() {
        _videos = page.videos;
        _packs = page.packs;
        _hasMore = page.hasMore;
        _slots.clear();
        _writing = null;
      });
    }, handle: _gone);
    if (mounted) setState(() => _videosFailed = !ok && !_leaving);
  }

  /// `not_found` from a read: the child is gone.
  bool _gone(ApiError e) {
    if (e.code != 'not_found') return false;
    _leave();
    return true;
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    unawaited(leaveForGoneChild(context, _model));
  }

  Future<void> _hide(FamilyVideo v) async {
    final api = AppScope.of(context).familyCatalog;
    setState(() {
      _writing = v.id;
      _notice = null;
    });
    final ok = await _hiding.run(
      () => api.hide(widget.id, v.id),
      handle: (e) => _videoGone(e, v),
    );
    if (!ok || !mounted) return;
    setState(() => _slots[v.id] = _Slot.hidden);
    // The notice in the row's slot is a live region, so the outcome is
    // heard; focus follows to the way back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _undoFocus.requestFocus();
    });
  }

  Future<void> _undo(FamilyVideo v) async {
    final api = AppScope.of(context).familyCatalog;
    setState(() => _writing = v.id);
    final ok = await _hiding.run(
      () => api.unhide(widget.id, v.id),
      handle: (e) => _videoGone(e, v),
    );
    if (ok && mounted) setState(() => _slots.remove(v.id));
  }

  /// A write answered `not_found`: the video left the catalogue, and its
  /// slot says so.
  bool _videoGone(ApiError e, FamilyVideo v) {
    if (e.code != 'not_found') return false;
    setState(() => _slots[v.id] = _Slot.gone);
    return true;
  }

  Future<void> _deleteProfile(Minor minor) async {
    final api = AppScope.of(context).family;
    final confirmed = await confirmDestructive(
      context,
      title: 'Excluir perfil',
      body: [
        'O perfil de ${minor.nickname} será apagado na hora: o apelido, o '
            'avatar, a faixa de idade e o que a criança assistiu, os vídeos '
            'e os totais de tempo de tela.',
        'O consentimento que você deu para o cadastro é retirado. Guardamos '
            'apenas o registro de que você consentiu e quando, sem nenhum '
            'dado da criança.',
      ],
      action: 'Excluir perfil',
    );
    if (!confirmed || !mounted) return;
    final ok = await _delete.write(
      () => api.deleteMinor(widget.id),
      handle: _gone,
    );
    if (!ok || !mounted) return;
    _leaving = true;
    await _model.refresh();
    if (mounted) context.go(Routes.children);
  }

  void _go(String path, {Object? extra}) {
    setState(() => _notice = null);
    context.go(path, extra: extra);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _reading, _hiding, _delete]),
    builder: (context, _) {
      Minor? minor;
      if (_model.state case FamilyReady(:final family)) {
        minor = family.minors.where((m) => m.id == widget.id).firstOrNull;
        // Opened for a child the family does not hold, or removed while
        // open.
        if (minor == null) scheduleMicrotask(_leave);
      }
      // System back goes where the arrow goes, not to the route beneath:
      // opened from Início, that is Início.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.go(widget.back);
        },
        child: FieldLayout(
          title: minor?.nickname ?? 'Criança',
          titleLeading: minor == null
              ? null
              : AvatarDisc(minor.avatar, size: 72, excludeSemantics: true),
          titleLine: minor?.ageBand.label,
          onBack: () => context.go(widget.back),
          children: minor == null ? familyPending(_model) : _page(minor),
        ),
      );
    },
  );

  List<Widget> _page(Minor minor) => [
    if (!minor.consentCurrent) ...[
      // Kid mode is paused for this child until a guardian authorizes the
      // profile again.
      Doors(
        children: [
          DoorRow(
            title: needsConsent,
            onTap: () => _go(Routes.reconsent(widget.id)),
          ),
        ],
      ),
      const SizedBox(height: Space.xl),
    ],
    KeyedSubtree(key: ChildPage.todayKey, child: _today(minor)),
    const SizedBox(height: Space.xxl),
    KeyedSubtree(key: ChildPage.videosKey, child: _videosSection(minor)),
    const SizedBox(height: Space.xxl),
    KeyedSubtree(key: ChildPage.profileKey, child: _profile(minor)),
  ];

  Widget _today(Minor minor) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Hoje'),
        const SizedBox(height: Space.md),
        TodayTime(_rules),
        FutureBuilder(
          future: _rules,
          builder: (context, read) => read.hasError
              ? QuietAction(label: 'Tentar de novo', onPressed: _readDay)
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: Space.xl),
        PrimaryButton(
          label: 'Mais tempo hoje',
          onPressed: () => _go(Routes.moreTime(widget.id)),
        ),
        const SizedBox(height: Space.md),
        FutureBuilder(
          future: _rules,
          builder: (context, read) {
            final limits = [
              if (read.data case final rules?) ...[
                ScreenTimeWords.rules(rules),
                if (rules.isDefault) 'Padrão da faixa ${_band(minor.ageBand)}',
              ],
            ];
            return Doors(
              children: [
                DoorRow(
                  title: 'Limite e horário',
                  semanticsLabel: ['Limite e horário', ...limits].join(', '),
                  onTap: () => _go(Routes.timeRules(widget.id)),
                  child: limits.isEmpty
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final line in limits) Text(line, style: muted),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
        FutureBuilder(
          future: _week,
          builder: (context, read) {
            final week = read.data;
            if (week == null) return const SizedBox.shrink();
            // Today is the section's own modules and words; the list
            // holds the six days before it.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.xl),
                Semantics(
                  header: true,
                  child: Text('Dias anteriores', style: text.titleMedium),
                ),
                const SizedBox(height: Space.md),
                Doors(
                  children: [
                    for (final (i, day) in week.indexed.skip(1))
                      FigureRow(
                        label: ScreenTimeWords.day(i, day.date),
                        figure: ScreenTimeWords.watched(day.watched),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _videosSection(Minor minor) {
    final text = Theme.of(context).textTheme;
    final videos = _videos;
    final nickname = minor.nickname;
    final thumbnail = AppScope.of(context).familyCatalog.thumbnail;
    final List<Widget> body;
    if (videos == null) {
      body = [
        if (!_videosFailed)
          const FamilyPlaceholder(label: 'Carregando os vídeos')
        else ...[
          if (_reading.message case final message?) ...[
            ErrorNote(message),
            const SizedBox(height: Space.md),
          ],
          QuietAction(
            label: 'Tentar de novo',
            busy: _reading.busy,
            onPressed: _reading.blocked ? null : _readVideos,
          ),
        ],
      ];
    } else if (videos.isEmpty) {
      body = [Text(CatalogWords.empty(minor.ageBand), style: text.bodyLarge)];
    } else {
      // The page lists what the child sees: a video hidden already waits
      // in the full list, saying so.
      final shown = [
        for (final v in videos)
          if (!v.hidden || _slots.containsKey(v.id)) v,
      ].take(ChildPage.firstVideos).toList();
      final more = _hasMore || videos.length > shown.length;
      body = [
        if (_packs.isNotEmpty) ...[
          const _GroupLabel(packsHeading),
          const SizedBox(height: Space.sm),
          Doors(
            children: [
              for (final p in _packs)
                PackRow(
                  key: ValueKey('pack-${p.id}'),
                  pack: p,
                  nickname: nickname,
                  thumbnail: thumbnail,
                  onTap: () =>
                      _go(Routes.familyPack(widget.id, p.id), extra: p),
                ),
            ],
          ),
          const SizedBox(height: Space.xl),
        ],
        _GroupLabel('Liberados para $nickname'),
        const SizedBox(height: Space.sm),
        Doors(
          children: [
            if (shown.isEmpty)
              _ReadLine('Os vídeos liberados estão escondidos para $nickname.')
            else
              for (final v in shown) _videoSlot(v, nickname),
            if (more)
              DoorRow(
                title: 'Ver todos os vídeos',
                onTap: () => _go(Routes.childVideos(widget.id)),
              ),
          ],
        ),
      ];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Vídeos'),
        const SizedBox(height: Space.md),
        if (_notice case final notice?) ...[
          Notice(notice),
          const SizedBox(height: Space.lg),
        ],
        ...body,
      ],
    );
  }

  /// One video between the hairlines: its row with a quiet "Esconder" under
  /// its words, or, once hidden, the notice in the slot the row left with
  /// "Desfazer".
  Widget _videoSlot(FamilyVideo v, String nickname) {
    final here = _writing == v.id;
    final message = here ? _hiding.message : null;
    final idle = !_hiding.blocked;
    final busy = here && _hiding.busy;
    final error = [
      if (message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.md),
      ],
    ];
    switch (_slots[v.id]) {
      case _Slot.gone:
        return Padding(
          key: ValueKey(v.id),
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: const Notice(videoGone),
        );
      case _Slot.hidden:
        // The outcome holds the slot the row left, so it never reads as
        // the next video's state.
        return Padding(
          key: ValueKey(v.id),
          padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Notice(CatalogWords.hidden(nickname)),
              const SizedBox(height: Space.xs),
              QuietAction(
                label: 'Desfazer',
                focusNode: _undoFocus,
                semanticsLabel: 'Mostrar “${v.title}” para $nickname de novo',
                busy: busy,
                onPressed: idle ? () => _undo(v) : null,
              ),
              ...error,
            ],
          ),
        );
      case null:
        final large = rowTextIsLarge(context);
        final hide = QuietAction(
          label: 'Esconder',
          semanticsLabel: 'Esconder “${v.title}” para $nickname',
          inline: true,
          busy: busy,
          onPressed: idle ? () => _hide(v) : null,
        );
        final row = VideoRow(
          video: v,
          nickname: nickname,
          thumbnail: AppScope.of(context).familyCatalog.thumbnail,
          onTap: () => _go(Routes.familyVideo(widget.id, v.id), extra: v),
        );
        return Column(
          key: ValueKey(v.id),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // "Esconder" stands under the row's words, outside its target,
            // so the title keeps the line's width; its 48 dp target rises
            // into the row's foot so the word sits close under the line.
            // At large text the picture is gone and it starts on the
            // column's edge.
            Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: _hideRise),
                  child: row,
                ),
                PositionedDirectional(
                  start: large ? 0 : VideoThumb.size.width + Space.lg,
                  bottom: 0,
                  child: hide,
                ),
              ],
            ),
            ...error,
          ],
        );
    }
  }

  /// How far "Esconder"'s 48 dp target reaches below its row. Its label
  /// (about 20 px) sits centred, 14 px under the target's top; to set the
  /// word 8 px (sm) under the row's line, past the row's 16 px foot, the
  /// target rises 22 px into the row and the other 26 px stand below it.
  static const _hideRise = 26.0;

  Widget _profile(Minor minor) {
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted);
    final idle = !_delete.blocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Perfil'),
        const SizedBox(height: Space.md),
        Doors(
          children: [
            Row(
              children: [
                Expanded(
                  child: DoorRow(
                    title: minor.nickname,
                    semanticsLabel: [
                      minor.nickname,
                      minor.avatar.label,
                      minor.ageBand.label,
                    ].join(', '),
                    leading: AvatarDisc(
                      minor.avatar,
                      size: 56,
                      excludeSemantics: true,
                    ),
                    onTap: null,
                    child: Text(minor.ageBand.label, style: muted),
                  ),
                ),
                const SizedBox(width: Space.sm),
                QuietAction(
                  label: 'Editar',
                  semanticsLabel: 'Editar o perfil de ${minor.nickname}',
                  inline: true,
                  onPressed: idle
                      ? () => _go(Routes.editChild(widget.id))
                      : null,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: Space.xxl),
        if (_delete.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.md),
        ],
        QuietAction(
          label: 'Excluir perfil',
          destructive: true,
          busy: _delete.busy,
          onPressed: idle ? () => _deleteProfile(minor) : null,
        ),
      ],
    );
  }

  /// The band as the line says it: "5 a 8 anos", "2 a 4 anos".
  static String _band(AgeBand band) => switch (band) {
    AgeBand.unknown => 'de idade',
    _ => band.label,
  };
}

/// A line read between the hairlines in a row's place, never a target.
class _ReadLine extends StatelessWidget {
  const _ReadLine(this.words);

  final String words;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Text(words, style: Theme.of(context).textTheme.bodyLarge),
    ),
  );
}

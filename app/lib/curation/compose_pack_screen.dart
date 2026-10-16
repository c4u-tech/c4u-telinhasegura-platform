import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../catalog/video_row.dart' show VideoThumb;
import '../kid/shelves.dart' show ThumbnailLoader;
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/profile_fields.dart' show ChoiceTarget, SelectableRow;
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'curation.dart';
import 'pack.dart';
import 'pack_draft.dart';
import 'packs_screen.dart' show leaveForPacks;
import 'role_gate.dart';
import 'words.dart';

/// Under the primary while too few videos are picked.
String needsVideos(int min) => 'Escolha pelo menos $min vídeos.';

/// Under the primary while the name is blank.
const needsName = 'Dê um nome ao pacotinho.';

/// Under the primary while the total passes the longest allowed.
const overLimit = 'Os vídeos passam do tempo de um pacotinho. Tire um.';

/// In the picker once the picks reach the most a pacotinho holds.
const pickerFull = 'Até 5 vídeos por pacotinho.';

/// The done states.
const packSent = 'Seu pacotinho foi para a revisão.';
const versionSent = 'A nova versão foi para a revisão.';

/// The longest name, in characters.
const nameMax = 40;

/// A `pack_invalid` reason in words, at the section it broke.
String invalidMessage(String reason) => switch (PackInvalidReason.parse(
  reason,
)) {
  PackInvalidReason.count => 'Um pacotinho tem de 3 a 5 vídeos.',
  PackInvalidReason.repeat => 'Um vídeo aparece duas vezes. Tire a repetição.',
  PackInvalidReason.notApproved =>
    'Um dos vídeos saiu do catálogo. Tire esse vídeo e escolha outro.',
  PackInvalidReason.duration =>
    'Os vídeos passam do tempo de um pacotinho. Tire um.',
  PackInvalidReason.cover =>
    'A capa precisa ser de um dos vídeos do pacotinho.',
  PackInvalidReason.title => 'Dê um nome de 1 a 40 caracteres.',
  PackInvalidReason.unknown =>
    'Esse pacotinho não pôde ser enviado. Confira os vídeos e o nome.',
};

enum _Section { videos, name, cover, general }

_Section _sectionOf(PackInvalidReason r) => switch (r) {
  PackInvalidReason.count ||
  PackInvalidReason.repeat ||
  PackInvalidReason.notApproved ||
  PackInvalidReason.duration => _Section.videos,
  PackInvalidReason.cover => _Section.cover,
  PackInvalidReason.title => _Section.name,
  PackInvalidReason.unknown => _Section.general,
};

/// `/pacotinhos/novo` "Montar pacotinho", and `/pacotinhos/:id/mudar`
/// "Mudar pacotinho" prefilled with the current round:
/// the videos in order, each with "Subir",
/// "Descer" and "Tirar", and the total against the limit; the door to
/// the picker; the name; the cover from the videos' thumbnails; the
/// optional theme; and "Enviar para revisão", waiting with what is
/// missing. A broken composition is worded at the section it broke.
class ComposePackScreen extends StatefulWidget {
  const ComposePackScreen({super.key, this.id});

  /// The pacotinho recomposed; null for a new one.
  final String? id;

  @override
  State<ComposePackScreen> createState() => _ComposePackScreenState();
}

class _ComposePackScreenState extends State<ComposePackScreen> {
  final _draft = PackDraft();
  final _name = TextEditingController();
  final _send = Submission();
  final _up = <String, FocusNode>{};
  final _down = <String, FocusNode>{};
  bool _started = false;
  bool _done = false;

  /// Null until a recompose has read its pacotinho; a new one is ready.
  bool _ready = false;
  bool _failed = false;
  (_Section, String)? _invalid;

  bool get _recompose => widget.id != null;

  @override
  void initState() {
    super.initState();
    _name.addListener(_edited);
    _draft.addListener(_edited);
  }

  void _edited() {
    _send.clearMessage();
    if (_invalid != null) setState(() => _invalid = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    scheduleMicrotask(_readLimits);
    _ready = !_recompose;
    if (_recompose) scheduleMicrotask(_readPack);
  }

  @override
  void dispose() {
    _name.dispose();
    _draft.dispose();
    _send.dispose();
    for (final n in [..._up.values, ..._down.values]) {
      n.dispose();
    }
    super.dispose();
  }

  /// The server's limits; until they come, the fixed count rule holds
  /// and the total is shown without a bound.
  Future<void> _readLimits() async {
    if (!mounted) return;
    try {
      final limits = await AppScope.of(context).curation.packLimits();
      if (!mounted) return;
      setState(() => _draft.limits = limits);
    } on Object catch (e) {
      if (mounted) takeLostRole(context, e);
    }
  }

  Future<void> _readPack() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final p = await AppScope.of(context).curation.pack(widget.id!);
      if (!mounted) return;
      _name.text = p.title;
      _draft.prefill(p);
      setState(() => _ready = true);
    } on Object catch (e) {
      if (!mounted || leaveForPacks(context, e)) return;
      setState(() => _failed = true);
    }
  }

  String? get _missing {
    final min = _draft.limits.minVideos;
    if (_draft.videos.length < min) return needsVideos(min);
    if (_name.text.trim().isEmpty) return needsName;
    if (_draft.overLimit) return overLimit;
    return null;
  }

  Future<void> _submit() async {
    if (_missing != null) return;
    final api = AppScope.of(context).curation;
    final title = _name.text.trim();
    final ids = [for (final v in _draft.videos) v.id];
    final ok = await _send.run(
      () => _recompose
          ? api.recomposePack(
              widget.id!,
              title: title,
              videoIds: ids,
              coverVideoId: _draft.coverId,
              theme: _draft.theme,
            )
          : api.composePack(
              title: title,
              videoIds: ids,
              coverVideoId: _draft.coverId,
              theme: _draft.theme,
            ),
      handle: _handle,
    );
    if (ok && mounted) setState(() => _done = true);
  }

  bool _handle(ApiError e) {
    if (leaveForPacks(context, e)) return true;
    final reason = e.packInvalid;
    if (reason == null) return false;
    setState(
      () => _invalid = (_sectionOf(reason), invalidMessage(reason.wire)),
    );
    return true;
  }

  void _move(int from, int to) {
    final v = _draft.videos[from];
    _draft.move(from, to);
    final n = _draft.videos.length;
    // The moved video keeps the focus, on the key that still moves it.
    final next = to == 0
        ? _down[v.id]
        : to == n - 1
        ? _up[v.id]
        : (to < from ? _up[v.id] : _down[v.id]);
    WidgetsBinding.instance.addPostFrameCallback((_) => next?.requestFocus());
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${v.title}: vídeo ${to + 1} de $n',
        TextDirection.ltr,
      ),
    );
  }

  void _openPicker() => context.go(
    _recompose ? Routes.recomposeVideos(widget.id!) : Routes.newPackVideos,
    extra: _draft,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_send, _draft, _name]),
    builder: (context, _) => FieldLayout(
      title: _recompose ? 'Mudar pacotinho' : 'Montar pacotinho',
      onBack: () => context.go(
        _done || !_recompose ? Routes.packs : Routes.packReview(widget.id!),
      ),
      children: _done
          ? [
              Notice(_recompose ? versionSent : packSent),
              const SizedBox(height: Space.xl),
              PrimaryButton(
                label: 'Voltar para pacotinhos',
                onPressed: () => context.go(Routes.packs),
              ),
            ]
          : _ready
          ? _form()
          : _failed
          ? [
              const ErrorNote(Copy.genericRetry),
              const SizedBox(height: Space.lg),
              PrimaryButton(label: 'Tentar de novo', onPressed: _readPack),
            ]
          : const [FamilyPlaceholder(label: 'Carregando o pacotinho')],
    ),
  );

  List<Widget> _form() {
    final text = Theme.of(context).textTheme;
    final missing = _missing;
    final invalid = _invalid;
    String? at(_Section s) => invalid?.$1 == s ? invalid!.$2 : null;
    return [
      ..._heading('Vídeos'),
      ..._videos(),
      if (at(_Section.videos) case final m?) ...[
        const SizedBox(height: Space.md),
        ErrorNote(m),
      ],
      const SizedBox(height: Space.md),
      Doors(
        children: [
          DoorRow(
            title: 'Adicionar vídeos',
            semanticsLabel: 'Adicionar vídeos, Escolher por tema',
            onTap: _openPicker,
            child: Text(
              'Escolher por tema',
              style: text.bodyMedium?.copyWith(color: context.palette.muted),
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.xxl),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.sentences,
        maxLength: nameMax,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        buildCounter:
            (_, {required currentLength, required isFocused, maxLength}) =>
                currentLength < nameMax - 10
                ? null
                : Text(
                    '$currentLength de $nameMax',
                    style: text.bodySmall?.copyWith(
                      color: context.palette.muted,
                    ),
                  ),
        decoration: InputDecoration(
          labelText: 'Nome do pacotinho',
          helperText: 'As famílias leem este nome.',
          errorText: at(_Section.name),
          errorMaxLines: 3,
        ),
      ),
      ..._heading('Capa'),
      ..._covers(),
      if (at(_Section.cover) case final m?) ...[
        const SizedBox(height: Space.md),
        ErrorNote(m),
      ],
      ..._heading('Tema'),
      for (final t in VideoTheme.values.where((t) => t != VideoTheme.unknown))
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: SelectableRow(
            label: t.label,
            selected: _draft.theme == t,
            onTap: () => _draft.chooseTheme(t),
          ),
        ),
      SelectableRow(
        label: 'Sem tema',
        selected: _draft.theme == null,
        onTap: () => _draft.chooseTheme(null),
      ),
      const SizedBox(height: Space.xxl),
      if (at(_Section.general) ?? _send.message case final m?) ...[
        ErrorNote(m),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Enviar para revisão',
        busy: _send.busy,
        onPressed: missing != null || _send.blocked ? null : _submit,
      ),
      SubmitHint(missing ?? '', visible: missing != null, reserve: true),
    ];
  }

  List<Widget> _heading(String title) => [
    const SizedBox(height: Space.xl),
    Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
    const SizedBox(height: Space.md),
  ];

  List<Widget> _videos() {
    final text = Theme.of(context).textTheme;
    final videos = _draft.videos;
    final limits = _draft.limits;
    final words = CurationWords.joined([
      '${videos.length} de ${limits.maxVideos} vídeos',
      limits.maxDuration > Duration.zero
          ? '${CurationWords.duration(_draft.total)} de '
                '${limits.maxDuration.inMinutes}'
          : CurationWords.duration(_draft.total),
      if (_draft.overLimit) 'acima do limite',
    ]);
    return [
      if (videos.isEmpty)
        Text('Nenhum vídeo ainda.', style: text.bodyLarge)
      else
        Doors(
          children: [
            for (final (i, v) in videos.indexed)
              _OrderRow(
                position: i + 1,
                video: v,
                up: i == 0
                    ? null
                    : _OrderKey(
                        icon: Icons.arrow_upward_rounded,
                        tooltip: 'Subir ${v.title}',
                        focusNode: _up.putIfAbsent(v.id, FocusNode.new),
                        onPressed: () => _move(i, i - 1),
                      ),
                down: i == videos.length - 1
                    ? null
                    : _OrderKey(
                        icon: Icons.arrow_downward_rounded,
                        tooltip: 'Descer ${v.title}',
                        focusNode: _down.putIfAbsent(v.id, FocusNode.new),
                        onPressed: () => _move(i, i + 1),
                      ),
                out: _OrderKey(
                  icon: Icons.close_rounded,
                  tooltip: 'Tirar ${v.title}',
                  onPressed: () => _draft.remove(i),
                ),
              ),
          ],
        ),
      // The bounded set counted in modules, as the home counts its own;
      // no total while nothing is picked.
      if (videos.isNotEmpty) ...[
        const SizedBox(height: Space.md),
        CapacityRow(
          filled: videos.length,
          total: limits.maxVideos,
          words: words,
        ),
      ],
    ];
  }

  List<Widget> _covers() {
    final videos = _draft.videos;
    if (videos.isEmpty) {
      return [
        Text(
          'Escolha os vídeos primeiro.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ];
    }
    final thumbs = AppScope.of(context).familyCatalog.thumbnail;
    final cover = _draft.coverId;
    return [
      // Three to a row at every width; each tile takes the column's third.
      LayoutBuilder(
        builder: (context, box) {
          final width = (box.maxWidth - Space.md * 2) / 3;
          return Wrap(
            spacing: Space.md,
            runSpacing: Space.lg,
            children: [
              for (final (i, v) in videos.indexed)
                SizedBox(
                  width: width,
                  child: _CoverChoice(
                    position: i + 1,
                    video: v,
                    chosen: v.id == cover,
                    thumbnail: thumbs,
                    onTap: () => _draft.chooseCover(v.id),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }
}

/// One cover choice: the video's thumbnail at the tile's width, then
/// its state module and "2 · Sapo Cururu" on up to two lines, so the
/// choice reads without the picture. The chosen one strokes the
/// thumbnail's own screen in ink, as a chosen row strokes itself.
class _CoverChoice extends StatelessWidget {
  const _CoverChoice({
    required this.position,
    required this.video,
    required this.chosen,
    required this.thumbnail,
    required this.onTap,
  });

  final int position;
  final PickedVideo video;
  final bool chosen;
  final ThumbnailLoader thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ChoiceTarget(
      label: 'Capa: ${video.title}',
      selected: chosen,
      onTap: onTap,
      radius: Radii.small,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final h = w * 9 / 16;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: w,
                height: h,
                foregroundDecoration: chosen
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          h * Radii.screenRatio,
                        ),
                        border: Border.all(color: p.action, width: 2.5),
                      )
                    : null,
                child: FittedBox(
                  child: VideoThumb(
                    key: ValueKey(video.id),
                    videoId: video.id,
                    thumbnail: thumbnail,
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: StateModule(filled: chosen),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      // The number never parts from the title's first word.
                      '$position\u00A0·\u00A0${video.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One picked video in the composer: "2. Sapo Cururu" and "Canal · 4 min"
/// muted, its keys beside it, or beneath it when the words need the
/// width (200 % text, narrow columns).
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.position,
    required this.video,
    required this.up,
    required this.down,
    required this.out,
  });

  final int position;
  final PickedVideo video;
  final Widget? up;
  final Widget? down;
  final Widget out;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$position. ${video.title}', style: text.bodyLarge),
        const SizedBox(height: Space.xs),
        Text(
          CurationWords.joined([
            if (video.channelTitle.isNotEmpty) video.channelTitle,
            CurationWords.duration(video.duration),
          ]),
          style: text.bodyMedium?.copyWith(color: context.palette.muted),
        ),
      ],
    );
    // Each key keeps its slot, so the others never shift when one goes.
    final keys = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        up ?? const SizedBox.square(dimension: _OrderKey.size),
        const SizedBox(width: Space.xs),
        down ?? const SizedBox.square(dimension: _OrderKey.size),
        const SizedBox(width: Space.xs),
        out,
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: LayoutBuilder(
        builder: (context, box) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final stacked = scale > 1.3 || box.maxWidth < 340;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                words,
                const SizedBox(height: Space.sm),
                Align(alignment: Alignment.centerRight, child: keys),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: words),
              const SizedBox(width: Space.sm),
              keys,
            ],
          );
        },
      ),
    );
  }
}

/// One outlined 48 dp key of the reorder row, read by its [tooltip].
class _OrderKey extends StatelessWidget {
  const _OrderKey({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.focusNode,
  });

  static const size = 48.0;

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: OutlinedButton(
        focusNode: focusNode,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.square(size),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(size * Radii.screenRatio),
          ),
        ),
        child: Icon(icon, semanticLabel: tooltip, size: 24),
      ),
    ),
  );
}

/// `/pacotinhos/novo/videos` (and `/pacotinhos/:id/mudar/videos`)
/// "Adicionar vídeos": the six themes; a theme chosen lists its approved
/// videos as choices, the picked ones selected; at the most a pacotinho
/// holds the rest wait. "Pronto" brings the picks back to the composer;
/// back brings nothing. Opened
/// without its composer's [draft], it goes to the composer.
class PackPickerScreen extends StatefulWidget {
  const PackPickerScreen({super.key, required this.back, this.draft});

  /// The composer's path.
  final String back;
  final PackDraft? draft;

  @override
  State<PackPickerScreen> createState() => _PackPickerScreenState();
}

class _PackPickerScreenState extends State<PackPickerScreen> {
  final _more = Submission();
  bool _started = false;
  late final List<PickedVideo> _picks = [...?widget.draft?.videos];
  VideoTheme? _theme;
  VideoTheme? _firstBrowsed;
  List<Video>? _videos;
  int? _next;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    if (widget.draft == null) {
      scheduleMicrotask(() {
        if (mounted) context.go(widget.back);
      });
    }
  }

  @override
  void dispose() {
    _more.dispose();
    super.dispose();
  }

  int get _max => widget.draft?.limits.maxVideos ?? 5;

  Future<void> _choose(VideoTheme t) async {
    _firstBrowsed ??= t;
    setState(() {
      _theme = t;
      _videos = null;
      _next = null;
      _failed = false;
    });
    try {
      final page = await AppScope.of(context).curation.approvedVideos(t);
      if (!mounted || _theme != t) return;
      setState(() {
        _videos = page.videos;
        _next = page.nextOffset;
      });
    } on Object catch (e) {
      if (!mounted || takeLostRole(context, e)) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _readMore(VideoTheme t, int offset) async {
    final api = AppScope.of(context).curation;
    late QueuePage page;
    final ok = await _more.run(
      () async => page = await api.approvedVideos(t, offset: offset),
      handle: (e) => takeLostRole(context, e),
    );
    if (!ok || !mounted || _theme != t) return;
    setState(() {
      _videos = [...?_videos, ...page.videos];
      _next = page.nextOffset;
    });
  }

  void _toggle(Video v) {
    final picked = PickedVideo.of(v);
    setState(() {
      if (!_picks.remove(picked)) _picks.add(picked);
    });
  }

  void _done() {
    widget.draft?.take(_picks, browsed: _firstBrowsed);
    context.go(widget.back);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _more,
    builder: (context, _) => FieldLayout(
      title: 'Adicionar vídeos',
      onBack: () => context.go(widget.back),
      children: [
        Semantics(
          header: true,
          child: Text('Tema', style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: Space.md),
        for (final t in VideoTheme.values.where((t) => t != VideoTheme.unknown))
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: SelectableRow(
              label: t.label,
              selected: _theme == t,
              onTap: () => _choose(t),
            ),
          ),
        const SizedBox(height: Space.xl),
        ..._list(),
        const SizedBox(height: Space.xxl),
        PrimaryButton(label: 'Pronto', onPressed: _done),
        SubmitHint(
          _picks.length == 1
              ? '1 vídeo escolhido'
              : '${_picks.length} vídeos escolhidos',
          visible: true,
          reserve: true,
        ),
      ],
    ),
  );

  List<Widget> _list() {
    final theme = _theme;
    if (theme == null) return const [];
    final videos = _videos;
    final text = Theme.of(context).textTheme;
    if (videos == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando os vídeos')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: () => _choose(theme)),
      ];
    }
    if (videos.isEmpty) {
      return [
        Text('Nenhum vídeo aprovado neste tema ainda.', style: text.bodyLarge),
      ];
    }
    final full = _picks.length >= _max;
    final next = _next;
    return [
      Semantics(
        header: true,
        child: Text('Vídeos de ${theme.label}', style: text.titleMedium),
      ),
      const SizedBox(height: Space.md),
      if (full) ...[
        Text(pickerFull, style: text.bodyLarge),
        const SizedBox(height: Space.md),
      ],
      for (final v in videos)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Builder(
            builder: (context) {
              final picked = _picks.contains(PickedVideo.of(v));
              return SelectableRow(
                label: v.title,
                detail: CurationWords.joined([
                  v.channelTitle,
                  CurationWords.duration(v.duration),
                  ?v.minAgeBand?.label,
                ]),
                selected: picked,
                onTap: picked || !full ? () => _toggle(v) : null,
              );
            },
          ),
        ),
      if (next != null) ...[
        const SizedBox(height: Space.lg),
        if (_more.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.sm),
        ],
        QuietAction(
          label: 'Ver mais',
          busy: _more.busy,
          onPressed: _more.blocked ? null : () => _readMore(theme, next),
        ),
      ],
    ];
  }
}

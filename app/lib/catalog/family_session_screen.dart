import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../curation/family_catalog.dart';
import '../curation/words.dart';
import '../design/field_layout.dart';
import '../design/pin_pad.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/child_page.dart' show leaveForGoneChild;
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/family_write.dart';
import '../family/widgets.dart';
import '../kid_mode/hand_over.dart';
import '../screentime/kid_time.dart';
import '../screentime/screentime_api.dart';
import '../screentime/time_choice.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'family_video_screen.dart' show findFamilyVideo;
import 'session_fit.dart';
import 'words.dart';

/// `/familia/videos/:crianca/:video/assistir`, titled "Assistir com Lia":
/// a long work the child watches only with the family, started on this
/// device behind the PIN. The work and its length, what is left of the
/// child's day and, when the work does not fit, how much it misses; then
/// the time choice, with the least more time that makes it fit chosen,
/// and the PIN pad, whose filled key starts. When no more time could make
/// it fit, the screen says so and offers neither.
///
/// Started, the device is handed to the child and lands on the child's
/// player for the work, which opens where the family stopped. A refusal
/// keeps the choice and says why, as the PIN door does.
class FamilySessionScreen extends StatefulWidget {
  const FamilySessionScreen({
    super.key,
    required this.minorId,
    required this.videoId,
    this.video,
  });

  final String minorId;
  final String videoId;
  final FamilyVideo? video;

  @override
  State<FamilySessionScreen> createState() => _FamilySessionScreenState();
}

class _FamilySessionScreenState extends State<FamilySessionScreen> {
  final _start = Submission();
  final _pad = PinPadController();
  late final FamilyModel _model;
  late final FamilyWrite _handOver;
  bool _started = false;
  bool _failed = false;
  bool _leaving = false;
  FamilyVideo? _video;
  ScreenTimeRules? _day;

  /// Where the pad stands, to bring it whole into view.
  final _padKey = GlobalKey();

  /// The more time chosen, in minutes; 0 for none.
  int _minutes = 0;

  /// After a start lost on the way, the PIN typed, for one more try of
  /// the same start; let go of on any other outcome.
  String? _retry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    _handOver = FamilyWrite(
      family: _model,
      confirm: () => confirmItsYou(context),
    );
    _video = widget.video;
    scheduleMicrotask(_model.load);
    scheduleMicrotask(_read);
  }

  @override
  void dispose() {
    _retry = null;
    _start.dispose();
    _handOver.dispose();
    _pad.dispose();
    super.dispose();
  }

  /// Once a digit is typed, the whole pad, its start key included,
  /// stands in view: scrolled there at once, without motion.
  void _showPad() {
    final pad = _padKey.currentContext;
    if (pad == null) return;
    unawaited(
      Scrollable.ensureVisible(
        pad,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ),
    );
  }

  /// The work, when it came by its address, then the child's day.
  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final v =
          _video ??
          await findFamilyVideo(context, widget.minorId, widget.videoId);
      if (!mounted) return;
      if (v == null) return _toCatalogue();
      if (!v.familySession || v.hidden) {
        // Nothing to start here: the video's own screen says what it is.
        _leaving = true;
        return context.go(
          Routes.familyVideo(widget.minorId, widget.videoId),
          extra: v,
        );
      }
      final day = await AppScope.of(context).screenTime.rules(widget.minorId);
      if (!mounted) return;
      setState(() {
        _video = v;
        _show(day);
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 'not_found') return _toChildren();
      setState(() => _failed = true);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// The day as just read, with the least more time that fits chosen.
  void _show(ScreenTimeRules day) {
    _day = day;
    _minutes = SessionFit(day, _video!.left).smallest ?? 0;
  }

  /// The day again, after a refusal that said it changed; a failed read
  /// keeps the one shown.
  Future<void> _readDay() async {
    try {
      final day = await AppScope.of(context).screenTime.rules(widget.minorId);
      if (mounted) setState(() => _show(day));
    } on Object {
      // The note already says why the start did not happen.
    }
  }

  void _toCatalogue() {
    if (_leaving) return;
    _leaving = true;
    context.go(Routes.child(widget.minorId), extra: videoGone);
  }

  void _toChildren() {
    if (_leaving) return;
    _leaving = true;
    unawaited(leaveForGoneChild(context, _model));
  }

  Future<void> _begin(Minor minor, String pin) async {
    final services = AppScope.of(context);
    final here = Routes.familySession(widget.minorId, widget.videoId);
    var lost = false;
    setState(() => _retry = null);
    final ok = await _start.run(
      () async {
        try {
          await services.familySessions.start(
            minorId: widget.minorId,
            videoId: widget.videoId,
            pin: pin,
            extendMinutes: _minutes == 0 ? null : _minutes,
          );
        } on ApiError catch (e) {
          lost = e.status >= 500;
          rethrow;
        } on Object {
          lost = true;
          rethrow;
        }
      },
      overrides: {'time_up': CatalogWords.notNow(minor.nickname)},
      handle: (e) {
        switch (e.code) {
          case 'video_not_allowed':
            _toCatalogue();
            return true;
          case 'not_found':
            _toChildren();
            return true;
          case 'consent_required':
            _leaving = true;
            context.go(Routes.reconsent(widget.minorId, then: here));
            return true;
          case 'does_not_fit':
            // The day moved on: read it again, and choose again.
            unawaited(_readDay());
            return true;
          case 'time_up' || 'over_cap':
            unawaited(_readDay());
        }
        return false;
      },
    );
    if (!mounted) return;
    if (!ok) {
      if (lost) {
        setState(() => _retry = pin);
      } else {
        _pad.clear();
      }
      return;
    }
    _pad.clear();
    await handOverTo(
      context,
      _handOver,
      minor,
      then: Routes.watch(widget.videoId),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _start, _handOver]),
    builder: (context, _) {
      Minor? minor;
      if (_model.state case FamilyReady(:final family)) {
        minor = family.minors.where((m) => m.id == widget.minorId).firstOrNull;
        if (minor == null) scheduleMicrotask(_toChildren);
      }
      return FieldLayout(
        title: minor == null
            ? 'Assistir'
            : CatalogWords.watchWith(minor.nickname),
        onBack: () => context.go(
          Routes.familyVideo(widget.minorId, widget.videoId),
          extra: _video,
        ),
        children: minor == null ? familyPending(_model) : _body(minor),
      );
    },
  );

  List<Widget> _body(Minor minor) {
    final v = _video;
    final day = _day;
    if (v == null || day == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando o tempo de hoje')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    final nickname = minor.nickname;
    // What has to fit is what is left of the work, as the server counts.
    final fit = SessionFit(day, v.left);
    final smallest = fit.smallest;
    final now = day.today.time.state == KidTimeState.ok
        ? CatalogWords.dayLeft(nickname, fit.left)
        : CatalogWords.notNow(nickname);
    final dayLine = [
      now,
      if (smallest == null)
        CatalogWords.noFit
      else if (smallest > 0)
        CatalogWords.toFit(fit.shortfall),
    ].join(' ');
    final idle = !_start.blocked && !_handOver.blocked;
    final message = _start.message ?? _handOver.message;
    return [
      Text(v.title, style: text.titleMedium),
      const SizedBox(height: Space.xs),
      Text(
        v.resumeSeconds > 0
            ? CatalogWords.workLeft(v.left)
            : CurationWords.duration(v.duration),
        style: muted,
      ),
      const SizedBox(height: Space.lg),
      // Read again after a refusal: said aloud when it changes.
      Semantics(liveRegion: true, child: Text(dayLine, style: text.bodyLarge)),
      if (smallest != null) ...[
        const SizedBox(height: Space.xl),
        TimeChoice(
          chosen: _minutes == 0 ? null : _minutes,
          onChoose: idle
              ? (m) {
                  _start.clearMessage();
                  setState(() => _minutes = m ?? 0);
                }
              : null,
          plain: CatalogWords.noMoreTime,
          plainFirst: true,
          waits: (m) => !fit.fitsWith(m ?? 0),
        ),
        const SizedBox(height: Space.xl),
        Semantics(
          header: true,
          child: Text(CatalogWords.pinHeading, style: text.titleMedium),
        ),
        const SizedBox(height: Space.md),
        if (message != null) ...[
          ErrorNote(message),
          const SizedBox(height: Space.lg),
        ],
        if (_retry case final pin?) ...[
          PrimaryButton(
            label: 'Tentar de novo',
            busy: _start.busy,
            onPressed: idle ? () => _begin(minor, pin) : null,
          ),
          const SizedBox(height: Space.xl),
        ],
        Center(
          key: _padKey,
          child: PinPad(
            onTyped: _showPad,
            controller: _pad,
            enabled: idle,
            autofocus: false,
            confirmLabel: CatalogWords.begin,
            onSubmit: (pin) => _begin(minor, pin),
          ),
        ),
      ],
    ];
  }
}

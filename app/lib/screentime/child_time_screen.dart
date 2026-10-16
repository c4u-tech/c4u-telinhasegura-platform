import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/labels.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'refetch_on_return.dart';
import 'screen_time_screen.dart' show leaveForGoneChild;
import 'screentime_api.dart';
import 'words.dart';

/// `/familia/tempo/:id`: one child's screen time, titled by the nickname:
/// today in words, the doors to "Mais tempo hoje" and "Limite e
/// horário", then the last seven days, today first (screen-time screens).
/// It reads the rules and the usage again whenever the
/// guardian comes back from an errand.
class ChildTimeScreen extends StatefulWidget {
  const ChildTimeScreen({super.key, required this.id});

  final String id;

  @override
  State<ChildTimeScreen> createState() => _ChildTimeScreenState();
}

class _ChildTimeScreenState extends State<ChildTimeScreen>
    with RefetchOnReturn {
  final _reading = Submission();
  late final FamilyModel _model;
  bool _started = false;
  ScreenTimeRules? _rules;

  /// The seven days, today first.
  List<DayUsage>? _week;

  /// Set once the screen hands back to the list.
  bool _leaving = false;

  /// The last read failed: "Tentar de novo" stays, even once a rate
  /// limit's countdown has run out.
  bool _failed = false;

  @override
  String get ownPath => Routes.childTime(widget.id);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    watchReturns();
    scheduleMicrotask(_model.load);
    // Beneath an errand opened directly, it reads once shown.
    if (isHere) scheduleMicrotask(_read);
  }

  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  @override
  void onReturn() => unawaited(_read());

  Future<void> _read() async {
    final api = AppScope.of(context).screenTime;
    final ok = await _reading.run(() async {
      final read = await Future.wait<Object>([
        api.rules(widget.id),
        api.usage(widget.id),
      ], eagerError: true);
      if (!mounted) return;
      setState(() {
        _rules = read[0] as ScreenTimeRules;
        _week = (read[1] as List<DayUsage>).reversed.toList();
      });
    }, handle: _gone);
    if (mounted) setState(() => _failed = !ok && !_leaving);
  }

  Future<void> _toList() {
    _leaving = true;
    return leaveForGoneChild(context, _model);
  }

  bool _gone(ApiError e) {
    if (e.code != 'not_found') return false;
    if (!_leaving) unawaited(_toList());
    return true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _reading]),
    builder: (context, _) {
      Minor? minor;
      if (_model.state case FamilyReady(:final family)) {
        minor = family.minors.where((m) => m.id == widget.id).firstOrNull;
        if (minor == null && !_leaving) {
          // Opened for a child the family does not hold.
          _leaving = true;
          scheduleMicrotask(_toList);
        }
      }
      return FieldLayout(
        title: minor?.nickname ?? 'Tempo de tela',
        onBack: () => context.go(Routes.screenTime),
        children: _body(minor),
      );
    },
  );

  List<Widget> _body(Minor? minor) {
    final rules = _rules;
    final week = _week;
    final note = [
      if (_reading.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
    ];
    if (minor == null) return familyPending(_model);
    if (rules == null || week == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando o tempo de tela')];
      }
      return [
        ...note,
        PrimaryButton(
          label: 'Tentar de novo',
          busy: _reading.busy,
          onPressed: _reading.blocked ? null : _read,
        ),
      ];
    }
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    final limits = [
      ScreenTimeWords.rules(rules),
      if (rules.isDefault) 'Padrão da faixa ${_band(minor.ageBand)}',
    ];
    return [
      ...note,
      Text(ScreenTimeWords.today(rules), style: text.bodyLarge),
      if (ScreenTimeWords.extension(rules) case final extension?)
        Text(extension, style: text.bodyLarge),
      const SizedBox(height: Space.xl),
      Doors(
        children: [
          DoorRow(
            title: 'Mais tempo hoje',
            onTap: () => context.go(Routes.moreTime(widget.id)),
          ),
          DoorRow(
            title: 'Limite e horário',
            semanticsLabel: ['Limite e horário', ...limits].join(', '),
            onTap: () => context.go(Routes.timeRules(widget.id)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final line in limits) Text(line, style: muted)],
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.xxl),
      Semantics(
        header: true,
        child: Text('Últimos 7 dias', style: text.titleMedium),
      ),
      const SizedBox(height: Space.md),
      Doors(
        children: [
          for (final (i, day) in week.indexed)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                child: Text(
                  '${ScreenTimeWords.day(i, day.date)} · '
                  '${ScreenTimeWords.watched(day.watched)}',
                  style: text.bodyLarge,
                ),
              ),
            ),
        ],
      ),
    ];
  }

  /// The band in the line's lower case: "5 a 8 anos", "até 4 anos".
  static String _band(AgeBand band) => switch (band) {
    AgeBand.unknown => 'de idade',
    _ => band.label.replaceFirst('Até', 'até'),
  };
}

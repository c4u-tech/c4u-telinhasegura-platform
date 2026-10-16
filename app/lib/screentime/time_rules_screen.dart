import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/value_stepper.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'screen_time_screen.dart' show leaveForGoneChild;
import 'screentime_api.dart';
import 'words.dart';

/// The hours' rule, said at the hours, also for the server's
/// `validation` when the hours are its cause.
const rangeRule = 'O começo precisa ser antes do fim.';

/// The largest text scale at which the platform picker holds whole in
/// both dial and keyboard entry, at 360 × 640 and 1280 × 800: past it,
/// its keyboard entry overflows its own dialog. A smaller device scale
/// is kept as it is.
const pickerMaxTextScale = 1.2;

/// `/familia/tempo/:id/limite`: one child's daily limit in a stepper of
/// 15-minute steps from 15 to 240, the hours as two rows opening the
/// 24-hour picker, the family's zone in words, and "Salvar" (screen-time screens).
/// The bounds and the hours' order only spare a round
/// trip: the server enforces both.
class TimeRulesScreen extends StatefulWidget {
  const TimeRulesScreen({super.key, required this.id});

  final String id;

  @override
  State<TimeRulesScreen> createState() => _TimeRulesScreenState();
}

class _TimeRulesScreenState extends State<TimeRulesScreen> {
  final _reading = Submission();
  final _saving = Submission();
  late final FamilyModel _model;
  bool _started = false;
  bool _leaving = false;
  bool _failed = false;

  /// The rules as read, then what the guardian enters.
  ScreenTimeRules? _stored;
  int _minutes = 0;
  TimeOfDay _start = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 0, minute: 0);

  /// The start is not before the end.
  bool _outOfOrder = false;

  /// The rules as saved, once the errand is done.
  ScreenTimeRules? _saved;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    scheduleMicrotask(_model.load);
    scheduleMicrotask(_read);
  }

  @override
  void dispose() {
    _reading.dispose();
    _saving.dispose();
    super.dispose();
  }

  bool _gone(ApiError e) {
    if (e.code != 'not_found') return false;
    if (!_leaving) {
      _leaving = true;
      unawaited(leaveForGoneChild(context, _model));
    }
    return true;
  }

  Future<void> _read() async {
    final api = AppScope.of(context).screenTime;
    final ok = await _reading.run(() async {
      final rules = await api.rules(widget.id);
      if (!mounted) return;
      setState(() {
        _stored = rules;
        _minutes = rules.dailyMinutes;
        _start = _parse(rules.windowStart);
        _end = _parse(rules.windowEnd);
      });
    }, handle: _gone);
    if (mounted) setState(() => _failed = !ok && !_leaving);
  }

  static TimeOfDay _parse(String hhmm) {
    final [h, m] = hhmm.split(':');
    return TimeOfDay(hour: int.parse(h), minute: int.parse(m));
  }

  static String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  static int _minuteOfDay(TimeOfDay t) => t.hour * 60 + t.minute;

  /// The platform's picker in 24-hour form, set to [current], its text
  /// held at [pickerMaxTextScale].
  Future<TimeOfDay?> _pick(TimeOfDay current) => showTimePicker(
    context: context,
    initialTime: current,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        alwaysUse24HourFormat: true,
        textScaler: MediaQuery.textScalerOf(context)
            .clamp(maxScaleFactor: pickerMaxTextScale),
      ),
      child: child!,
    ),
  );

  Future<void> _pickStart() async {
    if (_saving.blocked) return;
    if (await _pick(_start) case final t?) {
      setState(() {
        _start = t;
        _outOfOrder = false;
      });
    }
  }

  Future<void> _pickEnd() async {
    if (_saving.blocked) return;
    if (await _pick(_end) case final t?) {
      setState(() {
        _end = t;
        _outOfOrder = false;
      });
    }
  }

  bool get _inOrder => _minuteOfDay(_start) < _minuteOfDay(_end);

  Future<void> _save() async {
    if (!_inOrder) {
      setState(() => _outOfOrder = true);
      return;
    }
    final api = AppScope.of(context).screenTime;
    ScreenTimeRules? saved;
    final ok = await _saving.run(
      () async => saved = await api.saveRules(
        widget.id,
        dailyMinutes: _minutes,
        windowStart: _format(_start),
        windowEnd: _format(_end),
      ),
      handle: (e) {
        // `validation` also means bad minutes, a bad time or zone: it
        // reads as the hours' rule only when the hours are its cause.
        if (e.code == 'validation' && !_inOrder) {
          setState(() => _outOfOrder = true);
          return true;
        }
        return _gone(e);
      },
    );
    if (ok && mounted) setState(() => _saved = saved);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _reading, _saving]),
    builder: (context, _) {
      Minor? minor;
      if (_model.state case FamilyReady(:final family)) {
        minor = family.minors.where((m) => m.id == widget.id).firstOrNull;
        if (minor == null && !_leaving) {
          _leaving = true;
          scheduleMicrotask(() => leaveForGoneChild(context, _model));
        }
      }
      return FieldLayout(
        title: 'Limite e horário',
        onBack: () => context.go(Routes.childTime(widget.id)),
        children: _body(minor),
      );
    },
  );

  List<Widget> _body(Minor? minor) {
    if (minor == null) return familyPending(_model);
    if (_saved case final saved?) return _done(minor, saved);
    final stored = _stored;
    if (stored != null) return _form(stored);
    if (!_failed) {
      return const [FamilyPlaceholder(label: 'Carregando o limite e horário')];
    }
    return [
      if (_reading.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Tentar de novo',
        busy: _reading.busy,
        onPressed: _reading.blocked ? null : _read,
      ),
    ];
  }

  List<Widget> _form(ScreenTimeRules stored) {
    final idle = !_saving.blocked;
    final start = 'Começa às ${_format(_start)}';
    final end = 'Termina às ${_format(_end)}';
    return [
      ValueStepper(
        label: 'Por dia',
        value: _minutes,
        min: 15,
        max: 240,
        step: 15,
        words: ScreenTimeWords.minutes,
        onChanged: idle ? (v) => setState(() => _minutes = v) : null,
      ),
      const SizedBox(height: Space.xl),
      Doors(
        children: [
          // While a save waits the rows stay as they are, and do nothing.
          DoorRow(
            title: start,
            onTap: _pickStart,
            errorText: _outOfOrder ? rangeRule : null,
          ),
          DoorRow(title: end, onTap: _pickEnd),
        ],
      ),
      const SizedBox(height: Space.md),
      Text(
        ScreenTimeWords.zone(stored.timeZone),
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: context.palette.muted),
      ),
      const SizedBox(height: Space.xl),
      if (_saving.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Salvar',
        busy: _saving.busy,
        onPressed: idle ? _save : null,
      ),
    ];
  }

  List<Widget> _done(Minor minor, ScreenTimeRules saved) => [
    Notice(
      'O limite de ${minor.nickname} agora é '
      '${ScreenTimeWords.minutes(saved.dailyMinutes)} por dia, das '
      '${saved.windowStart} às ${saved.windowEnd}.',
    ),
    const SizedBox(height: Space.xl),
    PrimaryButton(
      label: 'Voltar para o tempo de tela',
      onPressed: () => context.go(Routes.childTime(widget.id)),
    ),
  ];
}

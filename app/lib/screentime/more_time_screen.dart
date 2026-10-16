import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/profile_fields.dart' show SelectableRow;
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'screen_time_screen.dart' show leaveForGoneChild;

/// Under the primary until an amount is chosen.
const moreTimeHint = 'Escolha quanto tempo acima.';

/// The amounts the server accepts.
const _amounts = [15, 30, 60];

/// `/familia/tempo/:id/mais`: 15, 30 or 60 more minutes today for one
/// child, none chosen on arrival, then the done state naming the child
/// and the minutes (screen-time screens).
class MoreTimeScreen extends StatefulWidget {
  const MoreTimeScreen({super.key, required this.id});

  final String id;

  @override
  State<MoreTimeScreen> createState() => _MoreTimeScreenState();
}

class _MoreTimeScreenState extends State<MoreTimeScreen> {
  final _give = Submission();
  late final FamilyModel _model;
  bool _started = false;
  int? _minutes;

  /// The minutes given, once the errand is done.
  int? _given;
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    scheduleMicrotask(_model.load);
  }

  @override
  void dispose() {
    _give.dispose();
    super.dispose();
  }

  bool _gone(ApiError e) {
    if (e.code != 'not_found') return false;
    _leaving = true;
    unawaited(leaveForGoneChild(context, _model));
    return true;
  }

  Future<void> _extend(int minutes) async {
    final api = AppScope.of(context).screenTime;
    final ok = await _give.run(
      () => api.extend(widget.id, minutes),
      handle: _gone,
    );
    if (ok && mounted) setState(() => _given = minutes);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _give]),
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
        title: 'Mais tempo hoje',
        onBack: () => context.go(Routes.childTime(widget.id)),
        children: switch ((minor, _given)) {
          (final minor?, final given?) => _done(minor, given),
          (_?, null) => _form(),
          _ => familyPending(_model),
        },
      );
    },
  );

  List<Widget> _form() {
    final minutes = _minutes;
    final idle = !_give.blocked;
    return [
      for (final (i, amount) in _amounts.indexed) ...[
        if (i > 0) const SizedBox(height: Space.sm),
        SelectableRow(
          label: '$amount min',
          selected: amount == minutes,
          onTap: idle
              ? () {
                  _give.clearMessage();
                  setState(() => _minutes = amount);
                }
              : null,
        ),
      ],
      const SizedBox(height: Space.xl),
      if (_give.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: minutes == null ? 'Dar mais tempo' : 'Dar mais $minutes min',
        busy: _give.busy,
        onPressed: minutes != null && idle ? () => _extend(minutes) : null,
      ),
      SubmitHint(moreTimeHint, visible: minutes == null, reserve: true),
    ];
  }

  List<Widget> _done(Minor minor, int given) => [
    Notice('${minor.nickname} tem mais $given min hoje.'),
    const SizedBox(height: Space.xl),
    PrimaryButton(
      label: 'Voltar para o tempo de tela',
      onPressed: () => context.go(Routes.childTime(widget.id)),
    ),
  ];
}

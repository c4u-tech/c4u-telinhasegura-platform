import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/avatars.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'refetch_on_return.dart';
import 'screentime_api.dart';
import 'words.dart';

/// From a screen about a child the family no longer holds (`not_found`,
/// or absent from the family): back to the refreshed list with a notice.
Future<void> leaveForGoneChild(BuildContext context, FamilyModel model) async {
  await model.refresh();
  if (context.mounted) context.go(Routes.screenTime, extra: Copy.childGone);
}

/// A row whose rules could not be read.
const unreadToday = 'Não deu para carregar';

/// `/familia/tempo`: each child by avatar, nickname and today's screen
/// time in words, each row opening the child's hub (screen-time screens).
/// Each child is read on its own: one failed read says so on
/// its row only. [notice] is a calm line brought from a hub whose child
/// no longer exists.
class ScreenTimeScreen extends StatefulWidget {
  const ScreenTimeScreen({super.key, this.notice});

  final String? notice;

  @override
  State<ScreenTimeScreen> createState() => _ScreenTimeScreenState();
}

class _ScreenTimeScreenState extends State<ScreenTimeScreen>
    with RefetchOnReturn {
  late final FamilyModel _model;
  bool _started = false;

  /// The children the rows were read for, and each one's rules: null
  /// while the first read runs, a null entry where a read failed.
  String? _readFor;
  Map<String, ScreenTimeRules?>? _today;

  @override
  String get ownPath => Routes.screenTime;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    watchReturns();
    // Opened directly, the family is read here; it notifies the router,
    // so the read starts after this build.
    scheduleMicrotask(_model.load);
  }

  @override
  void onReturn() {
    if (_model.state case FamilyReady(:final family)) _read(family.minors);
  }

  /// Reads every child's rules at once; the rows wait for all of them.
  Future<void> _read(List<Minor> minors) async {
    final key = minors.map((m) => m.id).join(',');
    _readFor = key;
    final api = AppScope.of(context).screenTime;
    final read = await Future.wait([
      for (final minor in minors)
        api
            .rules(minor.id)
            .then<ScreenTimeRules?>(
              (r) => r,
              onError: (_) {
                return null;
              },
            ),
    ]);
    if (!mounted || _readFor != key) return;
    setState(
      () => _today = {for (final (i, m) in minors.indexed) m.id: read[i]},
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => FieldLayout(
      title: 'Tempo de tela',
      onBack: () => context.go(Routes.home),
      children: switch (_model.state) {
        FamilyReady(:final family) => _list(family.minors),
        _ => familyPending(_model),
      },
    ),
  );

  List<Widget> _list(List<Minor> minors) {
    final text = Theme.of(context).textTheme;
    if (minors.isEmpty) {
      return [Text('Cadastre uma criança primeiro.', style: text.bodyLarge)];
    }
    // Beneath a hub opened directly, the rows wait to be shown.
    if (isHere && _readFor != minors.map((m) => m.id).join(',')) {
      scheduleMicrotask(() => _read(minors));
    }
    final today = _today;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    return [
      if (widget.notice case final notice?) ...[
        Notice(notice),
        const SizedBox(height: Space.lg),
      ],
      if (today == null)
        const FamilyPlaceholder(label: 'Carregando o tempo de tela')
      else
        Doors(
          children: [
            for (final minor in minors) _row(minor, today[minor.id], muted),
          ],
        ),
    ];
  }

  DoorRow _row(Minor minor, ScreenTimeRules? rules, TextStyle? muted) {
    final words = rules == null ? unreadToday : ScreenTimeWords.state(rules);
    return DoorRow(
      title: minor.nickname,
      semanticsLabel: '${minor.nickname}, $words',
      leading: AvatarDisc(minor.avatar, size: 56, excludeSemantics: true),
      onTap: () => context.go(Routes.childTime(minor.id)),
      child: Text(words, style: muted),
    );
  }
}

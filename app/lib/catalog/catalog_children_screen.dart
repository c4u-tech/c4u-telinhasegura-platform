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
import 'words.dart';

/// From a screen about a child the family no longer holds (`not_found`,
/// or absent from the family): back to the refreshed list with a notice.
Future<void> leaveForGoneChild(BuildContext context, FamilyModel model) async {
  await model.refresh();
  if (context.mounted) context.go(Routes.familyVideos, extra: Copy.childGone);
}

/// `/familia/videos`: each child by avatar, nickname and band in words,
/// each row opening that child's catalogue. The family read says
/// it all; nothing else is read here. [notice] is a calm line brought
/// from a catalogue whose child no longer exists.
class CatalogChildrenScreen extends StatefulWidget {
  const CatalogChildrenScreen({super.key, this.notice});

  final String? notice;

  @override
  State<CatalogChildrenScreen> createState() => _CatalogChildrenScreenState();
}

class _CatalogChildrenScreenState extends State<CatalogChildrenScreen> {
  late final FamilyModel _model;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    // Opened directly, the family is read here; it notifies the router,
    // so the read starts after this build.
    scheduleMicrotask(_model.load);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => FieldLayout(
      title: 'Vídeos',
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
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    return [
      if (widget.notice case final notice?) ...[
        Notice(notice),
        const SizedBox(height: Space.lg),
      ],
      Doors(
        children: [
          for (final minor in minors)
            DoorRow(
              title: minor.nickname,
              semanticsLabel:
                  '${minor.nickname}, ${CatalogWords.bandRow(minor.ageBand)}',
              leading: AvatarDisc(
                minor.avatar,
                size: 56,
                excludeSemantics: true,
              ),
              onTap: () => context.go(Routes.childVideos(minor.id)),
              child: Text(CatalogWords.bandRow(minor.ageBand), style: muted),
            ),
        ],
      ),
    ];
  }
}

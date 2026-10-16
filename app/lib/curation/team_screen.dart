import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../screentime/refetch_on_return.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/challenge.dart';
import '../staff/staff.dart';
import 'role_gate.dart';
import 'team_words.dart';
import 'words.dart';

String _plain(String address) => address;

/// `/admin/equipe` "Equipe": every account holding a role, admins
/// included, as a door in server order (the longest-serving first): the
/// email in title-medium with its break marks, the roles in words muted
/// and joined by a dot; then the primary "Nomear alguém".
/// It reads the team again whenever the admin comes back from
/// a member. [notice] is a calm line brought back from a member's sheet.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, this.notice});

  final TeamNotice? notice;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> with RefetchOnReturn {
  bool _started = false;

  /// Null while the first read runs.
  List<StaffMember>? _team;
  bool _failed = false;

  @override
  String get ownPath => Routes.team;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    watchReturns();
    // Beneath a member opened directly, it reads once shown.
    if (isHere) scheduleMicrotask(_read);
  }

  @override
  void onReturn() => unawaited(_read());

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final team = await AppScope.of(context).staff.staff();
      if (mounted) setState(() => _team = team);
    } on Object catch (e) {
      if (!mounted ||
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _read)) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => FieldLayout(
    title: 'Equipe',
    onBack: () => context.go(Routes.admin),
    children: [
      if (widget.notice case final notice?) ...[
        Notice(notice(addressBreaks), semanticsLabel: notice(_plain)),
        const SizedBox(height: Space.xl),
      ],
      ..._list(),
      const SizedBox(height: Space.xl),
      PrimaryButton(
        label: 'Nomear alguém',
        onPressed: () => context.go(Routes.appoint),
      ),
    ],
  );

  List<Widget> _list() {
    final team = _team;
    // A failed read keeps the screen's one primary: the retry is quiet.
    if (_failed) {
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.sm),
        QuietAction(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    if (team == null) {
      return const [FamilyPlaceholder(label: 'Carregando a equipe')];
    }
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted);
    return [
      Doors(
        children: [
          for (final m in team)
            DoorRow(
              title: addressBreaks(m.email),
              semanticsLabel: TeamWords.member(m),
              onTap: () => context.go(Routes.member(m.accountId)),
              child: m.roles.isEmpty
                  ? null
                  : Text(
                      CurationWords.joined(TeamWords.roles(m)),
                      style: muted,
                    ),
            ),
        ],
      ),
    ];
  }
}

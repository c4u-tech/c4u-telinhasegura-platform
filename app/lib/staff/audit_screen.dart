import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../curation/role_gate.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'accounts.dart';
import 'audit_row.dart';
import 'challenge.dart';

/// The log with nothing in it.
const noStaffActions = 'Nenhuma ação da equipe ainda.';

/// `/admin/auditoria` "Auditoria": the staff audit log, newest first, as
/// read rows between hairlines, never doors (an account is
/// reached only through a reasoned search). "Ver mais" appends the next page while there is one. A lost
/// role goes home; an MFA refusal asks the second factor, then reads
/// again.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final _more = Submission();
  bool _started = false;

  /// Null while the first read runs.
  List<AuditAction>? _actions;
  int? _next;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    scheduleMicrotask(_read);
  }

  @override
  void dispose() {
    _more.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final page = await AppScope.of(context).accounts.auditLog();
      if (!mounted) return;
      setState(() {
        _actions = page.actions;
        _next = page.nextOffset;
      });
    } on Object catch (e) {
      if (!mounted ||
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _read)) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  Future<void> _readMore() async {
    final offset = _next;
    if (offset == null) return;
    final api = AppScope.of(context).accounts;
    late AuditPage page;
    final ok = await _more.run(
      () async => page = await api.auditLog(offset: offset),
      handle: (e) =>
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _readMore),
    );
    if (!ok || !mounted) return;
    setState(() {
      _actions = [...?_actions, ...page.actions];
      _next = page.nextOffset;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _more,
    builder: (context, _) => FieldLayout(
      title: 'Auditoria',
      onBack: () => context.go(Routes.admin),
      children: [
        Text(
          'Ações da equipe, das mais recentes para as mais antigas.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: context.palette.muted),
        ),
        const SizedBox(height: Space.xl),
        ..._list(),
      ],
    ),
  );

  List<Widget> _list() {
    final actions = _actions;
    if (actions == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando a auditoria')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    if (actions.isEmpty) {
      return [
        Text(noStaffActions, style: Theme.of(context).textTheme.bodyLarge),
      ];
    }
    return [
      Doors(children: [for (final a in actions) AuditActionRow(a)]),
      if (_next != null) ...[
        const SizedBox(height: Space.xxl),
        if (_more.message case final message?) ...[
          ErrorNote(message),
          const SizedBox(height: Space.sm),
        ],
        QuietAction(
          label: 'Ver mais',
          busy: _more.busy,
          onPressed: _more.blocked ? null : _readMore,
        ),
      ],
    ];
  }
}

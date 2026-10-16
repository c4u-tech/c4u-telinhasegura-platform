import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../screentime/refetch_on_return.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/account_words.dart';
import '../staff/accounts.dart';
import '../staff/challenge.dart';
import 'pack_words.dart';
import 'role_gate.dart';
import 'team_words.dart';
import 'words.dart';

/// `/admin`: the platform's numbers as Figure Rows with the suppression
/// line under them, then the admin's
/// doors, "Buscar uma conta", "Equipe", "Vídeos retidos", "Pacotinhos"
/// and "Auditoria", the middle three with their count once read
/// ("5 pessoas", "3 vídeos", "8 pacotinhos"); a count not read is left
/// out, the door still there.
/// Numbers that fail to read leave the
/// error note with "Tentar de novo" in their place, the doors usable.
/// It reads the numbers and the counts again whenever the admin comes
/// back.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with RefetchOnReturn {
  bool _started = false;
  int? _team;
  int? _held;
  String? _packs;

  /// Null while the numbers' read runs or after it failed.
  Metrics? _metrics;
  bool _metricsFailed = false;

  @override
  String get ownPath => Routes.admin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    watchReturns();
    if (isHere) scheduleMicrotask(_read);
  }

  @override
  void onReturn() => _read();

  void _read() {
    if (!mounted) return;
    final staff = AppScope.of(context).staff;
    unawaited(_readMetrics());
    unawaited(_count(staff.staff, (n) => _team = n));
    unawaited(_count(staff.heldVideos, (n) => _held = n));
    unawaited(_countPacks());
  }

  /// The platform's totals; the last ones read stay while they
  /// are read again.
  Future<void> _readMetrics() async {
    if (!mounted) return;
    setState(() => _metricsFailed = false);
    try {
      final metrics = await AppScope.of(context).accounts.metrics();
      if (mounted) setState(() => _metrics = metrics);
    } on Object catch (e) {
      if (!mounted ||
          takeLostRole(context, e) ||
          takeMfaRefusal(context, e, again: _readMetrics)) {
        return;
      }
      setState(() {
        _metrics = null;
        _metricsFailed = true;
      });
    }
  }

  /// The pacotinhos' first page, counted:
  /// "Mais de 50 pacotinhos" when it has more.
  Future<void> _countPacks() async {
    try {
      final page = await AppScope.of(context).curation.adminPacks();
      if (!mounted) return;
      setState(
        () => _packs = PackWords.count(page.packs.length, more: page.hasMore),
      );
    } on Object catch (e) {
      if (mounted && !takeLostRole(context, e)) {
        takeMfaRefusal(context, e, again: _countPacks);
      }
    }
  }

  Future<void> _count(
    Future<List<Object>> Function() read,
    void Function(int) set,
  ) async {
    try {
      final n = (await read()).length;
      if (mounted) setState(() => set(n));
    } on Object catch (e) {
      // A count not read is left out; a lost role goes home; the second
      // factor asked for, the count is read once it passes.
      if (mounted && !takeLostRole(context, e)) {
        takeMfaRefusal(context, e, again: () => _count(read, set));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted);
    final team = _team == null ? null : TeamWords.people(_team!);
    final held = _held == null ? null : CurationWords.videos(_held!);
    return FieldLayout(
      title: 'Administração',
      onBack: () => context.go(Routes.home),
      children: [
        ..._numbers(muted),
        const SizedBox(height: Space.xxl),
        Doors(
          children: [
            DoorRow(
              title: 'Buscar uma conta',
              semanticsLabel:
                  'Buscar uma conta, Por e-\u2060mail ou código, com motivo',
              onTap: () => context.go(Routes.accounts),
              child: Text(
                'Por e-\u2060mail ou código, com motivo',
                style: muted,
              ),
            ),
            DoorRow(
              title: 'Equipe',
              semanticsLabel: ['Equipe', ?team].join(', '),
              onTap: () => context.go(Routes.team),
              child: team == null ? null : Text(team, style: muted),
            ),
            DoorRow(
              title: 'Vídeos retidos',
              semanticsLabel: ['Vídeos retidos', ?held].join(', '),
              onTap: () => context.go(Routes.heldVideos),
              child: held == null ? null : Text(held, style: muted),
            ),
            DoorRow(
              title: 'Pacotinhos',
              semanticsLabel: ['Pacotinhos', ?_packs].join(', '),
              onTap: () => context.go(Routes.adminPacks),
              child: _packs == null ? null : Text(_packs!, style: muted),
            ),
            DoorRow(
              title: 'Auditoria',
              semanticsLabel: 'Auditoria, Ações da equipe',
              onTap: () => context.go(Routes.audit),
              child: Text('Ações da equipe', style: muted),
            ),
          ],
        ),
      ],
    );
  }

  /// The seven totals in their fixed order, then the suppression line;
  /// the placeholder while they load, the error note once they fail.
  List<Widget> _numbers(TextStyle? muted) {
    final m = _metrics;
    if (m == null) {
      if (!_metricsFailed) {
        return const [FamilyPlaceholder(label: 'Carregando os números')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _readMetrics),
      ];
    }
    String figure(int? n) =>
        AccountWords.figure(n, suppressedBelow: m.suppressedBelow);
    return [
      Doors(
        children: [
          for (final (label, n) in [
            ('Contas', m.accounts),
            ('Famílias', m.families),
            ('Crianças', m.minors),
            ('Aparelhos ativos', m.activeDevices),
            ('Vídeos no catálogo', m.publishedVideos),
            ('Pacotinhos publicados', m.publishedPacks),
            ('Denúncias nos últimos 7 dias', m.reports7d),
          ])
            FigureRow(label: label, figure: figure(n)),
        ],
      ),
      const SizedBox(height: Space.md),
      Text(AccountWords.suppression(m.suppressedBelow), style: muted),
    ];
  }
}

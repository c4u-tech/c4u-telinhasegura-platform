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
import '../staff/accounts.dart' show Metrics;
import '../staff/challenge.dart';
import 'role_gate.dart';

/// `/admin/numeros`: the platform's numbers as Figure Rows with the
/// suppression line under them. Numbers that fail to read leave the
/// error note with "Tentar de novo" in their place. It reads them again
/// whenever the admin comes back.
class NumbersScreen extends StatefulWidget {
  const NumbersScreen({super.key});

  @override
  State<NumbersScreen> createState() => _NumbersScreenState();
}

class _NumbersScreenState extends State<NumbersScreen> with RefetchOnReturn {
  bool _started = false;

  /// Null while the numbers' read runs or after it failed.
  Metrics? _metrics;
  bool _metricsFailed = false;

  @override
  String get ownPath => Routes.numbers;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
    watchReturns();
    if (isHere) scheduleMicrotask(_readMetrics);
  }

  @override
  void onReturn() => unawaited(_readMetrics());

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

  @override
  Widget build(BuildContext context) => FieldLayout(
    title: 'Números da plataforma',
    onBack: () => context.go(Routes.staffHome),
    children: _numbers(
      Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.palette.muted),
    ),
  );

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

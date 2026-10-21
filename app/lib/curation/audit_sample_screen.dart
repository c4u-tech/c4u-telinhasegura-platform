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
import '../staff/challenge.dart';
import 'curation.dart';
import 'role_gate.dart';
import 'words.dart';

/// The held videos' door to the audit.
const auditDoor = 'Auditoria das aprovações';
const auditDoorLine = 'Conferir uma amostra de aprovações recentes';

const sampleLead =
    'Uma amostra de aprovações dos últimos 30 dias que ninguém conferiu. '
    'Assista a cada vídeo e diga se concorda.';
const noSample = 'Nenhuma aprovação recente para conferir agora.';

/// `/moderacao/auditoria`: up to 10 recent approvals nobody audited,
/// drawn anew on every read, as doors to each video. It reads again
/// whenever the moderator comes back. [notice] is a calm line brought
/// back from a video.
class AuditSampleScreen extends StatefulWidget {
  const AuditSampleScreen({super.key, this.notice});

  final String? notice;

  @override
  State<AuditSampleScreen> createState() => _AuditSampleScreenState();
}

class _AuditSampleScreenState extends State<AuditSampleScreen>
    with RefetchOnReturn {
  bool _started = false;
  List<AuditCandidate>? _sample;
  bool _failed = false;

  @override
  String get ownPath => Routes.auditSample;

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
  void onReturn() => unawaited(_read());

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final sample = await AppScope.of(context).staff.auditSample();
      if (mounted) setState(() => _sample = sample);
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
    title: auditDoor,
    onBack: () => context.go(Routes.heldVideos),
    children: [
      if (widget.notice case final notice?) ...[
        Notice(notice),
        const SizedBox(height: Space.xl),
      ],
      Text(sampleLead, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: Space.xl),
      ..._list(),
    ],
  );

  List<Widget> _list() {
    final sample = _sample;
    if (sample == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando a amostra')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    if (sample.isEmpty) {
      return [Text(noSample, style: Theme.of(context).textTheme.bodyLarge)];
    }
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted);
    return [
      Doors(
        children: [
          for (final c in sample)
            DoorRow(
              title: c.video.title,
              titleMaxLines: 2,
              semanticsLabel: [
                c.video.title,
                c.video.channelTitle,
                CurationWords.duration(c.video.duration),
              ].join(', '),
              onTap: () => context.go(Routes.auditVideo(c.video.id), extra: c),
              child: Text(
                CurationWords.joined([
                  c.video.channelTitle,
                  CurationWords.duration(c.video.duration),
                ]),
                style: muted,
              ),
            ),
        ],
      ),
    ];
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../family/widgets.dart' show FamilyPlaceholder;
import '../shell/routes.dart';
import '../shell/services.dart';
import 'curation.dart';
import 'role_gate.dart';

const curatorTermsTitle = 'Termo da curadoria';
const curatorTermsLead =
    'Antes de revisar, leia o termo da curadoria. Se estiver de acordo, '
    'toque em Aceito.';
const curatorTermsAccept = 'Aceito';

/// `/curadoria/termo`: a curator who has not accepted the curator terms in
/// force lands here from any curation screen. The text is the server's,
/// and "Aceito" sends back the version shown, then returns to [then],
/// the screen that asked. Terms already accepted return at once.
class CuratorTermsScreen extends StatefulWidget {
  const CuratorTermsScreen({super.key, required this.then});

  final String then;

  @override
  State<CuratorTermsScreen> createState() => _CuratorTermsScreenState();
}

class _CuratorTermsScreenState extends State<CuratorTermsScreen> {
  final _accept = Submission();
  bool _started = false;
  CuratorTerms? _terms;
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
    _accept.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      final terms = await AppScope.of(context).curation.declaration();
      if (!mounted) return;
      if (terms.accepted) return context.go(widget.then);
      setState(() => _terms = terms);
    } on Object catch (e) {
      if (!mounted || takeLostRole(context, e)) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _agree(CuratorTerms terms) async {
    final api = AppScope.of(context).curation;
    final ok = await _accept.run(
      () => api.acceptDeclaration(terms.version),
      handle: (ApiError e) {
        if (takeLostRole(context, e)) return true;
        // Terms changed while they were read: the new ones are shown.
        if (e.code == 'declaration_outdated') unawaited(_read());
        return false;
      },
    );
    if (ok && mounted) context.go(widget.then);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _accept,
    builder: (context, _) => FieldLayout(
      title: curatorTermsTitle,
      onBack: () => context.go(Routes.home),
      children: _body(),
    ),
  );

  List<Widget> _body() {
    final terms = _terms;
    if (terms == null) {
      if (!_failed) {
        return const [FamilyPlaceholder(label: 'Carregando o termo')];
      }
      return [
        const ErrorNote(Copy.genericRetry),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'Tentar de novo', onPressed: _read),
      ];
    }
    final text = Theme.of(context).textTheme;
    return [
      Text(curatorTermsLead, style: text.bodyLarge),
      const SizedBox(height: Space.xl),
      Text(terms.text, style: text.bodyLarge),
      const SizedBox(height: Space.xl),
      if (_accept.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: curatorTermsAccept,
        busy: _accept.busy,
        onPressed: _accept.blocked ? null : () => _agree(terms),
      ),
    ];
  }
}

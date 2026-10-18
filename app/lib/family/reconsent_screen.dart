import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'consent.dart';
import 'family.dart';
import 'family_model.dart';
import 'family_write.dart';
import 'profile_fields.dart';
import 'widgets.dart';

/// What a child's row and hub say while the profile waits for a guardian
/// to authorize it again.
const needsConsent = 'Precisa de nova autorização';

/// `/familia/criancas/:id/autorizar`: an existing child's profile
/// authorized again under the current consent text, with its own heading
/// and declaration. Until then kid mode is paused for this child.
/// Done, the family is read again and the screen returns to [then], or to
/// the children.
class ReconsentScreen extends StatefulWidget {
  const ReconsentScreen({super.key, required this.id, this.then});

  final String id;

  /// Where to return: the hand-over that asked for it, or null for the
  /// children.
  final String? then;

  @override
  State<ReconsentScreen> createState() => _ReconsentScreenState();
}

class _ReconsentScreenState extends State<ReconsentScreen> {
  late final FamilyModel _model;
  late final FamilyWrite _write;
  bool _started = false;
  bool _agreed = false;

  /// Set once the screen hands back: the child vanishing from the family
  /// is then expected, not news.
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    _write = FamilyWrite(family: _model, confirm: () => confirmItsYou(context));
    scheduleMicrotask(_model.load);
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  String get _back => widget.then ?? Routes.children;

  /// Back to the children, with [notice] on the list.
  Future<void> _gone() async {
    _leaving = true;
    await _model.refresh();
    if (mounted) context.go(Routes.children, extra: Copy.childGone);
  }

  bool _handle(ApiError e) {
    if (e.code != 'not_found') return false;
    unawaited(_gone());
    return true;
  }

  Future<void> _authorize() async {
    final api = AppScope.of(context).family;
    // The consent goes with the version of the text on screen.
    assert(ConsentText.version == kConsentPolicyVersion);
    final ok = await _write.write(
      () => api.grantConsent(widget.id),
      handle: _handle,
    );
    if (!ok) return;
    _leaving = true;
    await _model.refresh();
    if (mounted) context.go(_back);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _write]),
    builder: (context, _) {
      Minor? minor;
      if (_model.state case FamilyReady(:final family)) {
        minor = family.minors.where((m) => m.id == widget.id).firstOrNull;
        if (minor == null && !_leaving) {
          // Opened for a child the family does not hold.
          _leaving = true;
          scheduleMicrotask(_gone);
        }
      }
      return FieldLayout(
        title: 'Consentimento',
        onBack: _write.busy ? null : () => context.go(_back),
        children: switch (minor) {
          final minor? => _consent(minor),
          null => familyPending(_model),
        },
      );
    },
  );

  List<Widget> _consent(Minor minor) => [
    // The child the consent is about.
    ChildSummary(
      nickname: minor.nickname,
      avatar: minor.avatar,
      ageBand: minor.ageBand,
    ),
    const SizedBox(height: Space.xl),
    const ConsentTextBlock(title: ConsentText.reconsentTitle),
    const SizedBox(height: Space.md),
    DeclarationRow(
      text: ConsentText.reconsentDeclaration,
      value: _agreed,
      onChanged: _write.busy ? null : (v) => setState(() => _agreed = v),
    ),
    const SizedBox(height: Space.xl),
    if (_write.message case final message?) ...[
      ErrorNote(message),
      const SizedBox(height: Space.lg),
    ],
    PrimaryButton(
      label: 'Autorizar',
      busy: _write.busy,
      onPressed: _agreed && !_write.blocked ? _authorize : null,
    ),
    SubmitHint(declarationHint, visible: !_agreed),
  ];
}

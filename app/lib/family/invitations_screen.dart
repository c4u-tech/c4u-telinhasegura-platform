import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'family.dart';
import 'family_model.dart';
import 'family_write.dart';
import 'labels.dart';
import 'widgets.dart';

/// What an invitation does, while none waits.
const noInvitations =
    'Nenhum convite esperando resposta. Quem você convidar recebe um '
    'e-\u2060mail com um link e entra na família ao abrir o app com esse mesmo '
    'e-\u2060mail. O convite vale por 7 dias.';

/// Under "Enviar convite" while the field holds no address.
const typeAnEmail = 'Escreva o e-\u2060mail de quem você quer convidar.';

/// `/familia/convites`, the owner's: the pending invitations with their
/// expiry, each with "Cancelar convite", and the invite form.
/// The confirmation of a sent invitation
/// words only what was typed, the same for every address.
class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  final _email = TextEditingController();
  late final FamilyModel _model;
  late final FamilyWrite _send;
  late final FamilyWrite _cancel;
  bool _started = false;

  /// The invitation being cancelled, whose row shows the progress.
  String? _pending;

  /// The calm lines after a send or a cancel, with the address set by the
  /// given function: break marks to show, plain to read.
  String Function(String Function(String) set)? _sent;
  String Function(String Function(String) set)? _cancelled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    Future<bool> confirm() => confirmItsYou(context);
    _send = FamilyWrite(family: _model, confirm: confirm, ownerOnly: true);
    _cancel = FamilyWrite(family: _model, confirm: confirm, ownerOnly: true);
    scheduleMicrotask(_model.load);
  }

  @override
  void dispose() {
    _email.dispose();
    _send.dispose();
    _cancel.dispose();
    super.dispose();
  }

  String get _typed => _email.text.trim();

  Future<void> _invite() async {
    final api = AppScope.of(context).family;
    final email = _typed;
    setState(() => _sent = null);
    final ok = await _send.write(
      () => api.invite(email),
      overrides: const {
        'limit_reached': Copy.adultsFull,
        'validation': 'Confira o e-\u2060mail e tente de novo.',
      },
    );
    if (!ok) return;
    _email.clear();
    await _model.refresh();
    if (!mounted) return;
    setState(() => _sent = (set) => 'Enviamos o convite para ${set(email)}.');
  }

  Future<void> _revoke(PendingInvitation invitation) async {
    final api = AppScope.of(context).family;
    setState(() {
      _pending = invitation.id;
      _cancelled = null;
    });
    final ok = await _cancel.write(
      () => api.revokeInvitation(invitation.id),
      handle: (ApiError e) {
        // Accepted, expired or cancelled elsewhere: show what is left.
        if (e.code == 'not_found') unawaited(_model.refresh());
        return false;
      },
    );
    if (ok) await _model.refresh();
    if (!mounted) return;
    setState(() {
      _pending = null;
      if (ok) {
        _cancelled = (set) =>
            'Cancelamos o convite para ${set(invitation.email)}.';
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _send, _cancel, _email]),
    builder: (context, _) => FieldLayout(
      title: 'Convites',
      onBack: () => context.go(Routes.home),
      children: switch (_model.state) {
        FamilyReady(:final family) => _page(family),
        _ => familyPending(_model),
      },
    ),
  );

  List<Widget> _page(Family family) {
    final text = Theme.of(context).textTheme;
    final invitations = family.invitations ?? const [];
    final adults = family.members.length + family.pendingInvitations;
    final full = adults >= kMaxAdults;
    final typed = _typed.contains('@');
    final now = DateTime.now();
    return [
      if (_cancel.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ] else if (_cancelled case final cancelled?) ...[
        Notice(cancelled(addressBreaks), semanticsLabel: cancelled((a) => a)),
        const SizedBox(height: Space.lg),
      ],
      if (invitations.isEmpty)
        Text(noInvitations, style: text.bodyLarge)
      else
        Doors(
          children: [
            for (final invitation in invitations)
              _InvitationRow(
                email: invitation.email,
                expiry: FamilyWords.expiry(invitation.expiresAt, now),
                busy: _cancel.busy && _pending == invitation.id,
                onCancel: _cancel.blocked ? null : () => _revoke(invitation),
              ),
          ],
        ),
      const SizedBox(height: Space.xl),
      CapacityRow(
        filled: adults,
        total: kMaxAdults,
        words: FamilyWords.adults(
          family.members.length,
          family.pendingInvitations,
        ),
      ),
      const SizedBox(height: Space.xxl),
      Text('Convidar responsável', style: text.titleMedium),
      const SizedBox(height: Space.md),
      EmailField(
        controller: _email,
        onSubmitted: (_) {
          if (typed && !full && !_send.blocked) _invite();
        },
      ),
      const SizedBox(height: Space.xl),
      if (_send.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ] else if (_sent case final sent?) ...[
        Notice(sent(addressBreaks), semanticsLabel: sent((a) => a)),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Enviar convite',
        busy: _send.busy,
        onPressed: typed && !full && !_send.blocked ? _invite : null,
      ),
      if (full)
        const SubmitHint(Copy.adultsFull)
      else
        SubmitHint(typeAnEmail, visible: !typed),
    ];
  }
}

/// A pending invitation: who it went to, when it expires, and a quiet
/// "Cancelar convite" (reversible: the owner can invite again).
class _InvitationRow extends StatelessWidget {
  const _InvitationRow({
    required this.email,
    required this.expiry,
    required this.busy,
    required this.onCancel,
  });

  final String email;
  final String expiry;
  final bool busy;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AddressText(email, style: text.titleMedium),
                const SizedBox(height: Space.xs),
                Text(
                  expiry,
                  style: text.bodyMedium?.copyWith(
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          QuietAction(
            label: 'Cancelar convite',
            busy: busy,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

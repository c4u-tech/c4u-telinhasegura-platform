import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../auth/apple_id_tokens.dart';
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'account_write.dart';

String _plain(String address) => address;

/// What the entry screen says once the account is gone.
const accountDeleted = 'Sua conta foi excluída.';

/// Shown when this build cannot run Sign in with Apple.
const appleUnavailable =
    'Sua conta entra com a Apple, e este aparelho não consegue confirmar '
    'isso agora. Para excluí-la, escreva para '
    'suporte@telinhasegura.coding4u.tech.';

/// Shown when Apple refused the confirmation.
const appleRejected = 'A Apple não confirmou a exclusão. Tente de novo.';

/// Shown when the Apple sheet failed rather than being cancelled.
const appleFailed =
    'Não foi possível confirmar com a Apple agora. Tente de novo.';

/// Shown for `apple_identity_mismatch`. It does not assert a mismatch: the
/// same code covers a verifier outage.
const appleMismatch =
    'Não foi possível confirmar que essa conta Apple é a ligada a esta '
    'conta. Se o problema continuar, escreva para '
    'suporte@telinhasegura.coding4u.tech.';

const _declaration =
    'Entendo que minha conta é apagada na hora e que isso não pode ser '
    'desfeito.';

/// `/conta/excluir`: the screen is the confirmation, as the family's
/// deletion is. It names what goes and, for a member, what stays (the
/// family and the children, the titular's), waits for a declaration, then
/// deletes through the re-authentication.
/// An owner is offered the two ways to hand the family on
/// instead, which a stale family's `owner_must_transfer` also
/// shows.
///
/// What the copy claims follows the server's deletion: the account, its
/// logins, sessions and membership go; the audit history and the consent
/// ledger stay, holding no email.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  late final FamilyModel _model;
  late final AccountWrite _write;
  bool _started = false;
  bool _declared = false;

  /// The Apple sheet is up: no second prompt meanwhile.
  bool _asking = false;

  /// The Apple credential for the next attempt, used once.
  AppleCredential? _apple;
  String? _appleNote;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    _model = services.familyModel;
    _write = AccountWrite(
      confirm: () => confirmItsYou(context),
      signOut: services.client.forgetSession,
    );
    // Whether the caller owns a family decides the screen; it notifies
    // the router, so after this build.
    scheduleMicrotask(_model.load);
  }

  @override
  void dispose() {
    _write.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final services = AppScope.of(context);
    final apple = _apple;
    _apple = null; // an authorization code is single-use
    setState(() => _appleNote = null);
    var askApple = false;
    await _write.write(
      () async {
        // Set before the sign-out lands on the entry screen, which takes
        // it once; any failure takes it back.
        services.entryNotice = accountDeleted;
        try {
          await services.privacy.deleteAccount(apple: apple);
        } on Object {
          services.entryNotice = null;
          rethrow;
        }
      },
      overrides: const {
        'apple_authorization_invalid': appleRejected,
        'apple_identity_mismatch': appleMismatch,
      },
      handle: (e) {
        if (e.code == 'apple_reauthorization_required') {
          // Still wanted after a credential was sent: say so rather than
          // asking again by itself.
          if (apple == null) {
            askApple = true;
          } else {
            _appleNote = appleRejected;
          }
          return true;
        }
        if (e.code != 'owner_must_transfer') return false;
        // The family changed hands meanwhile: read it again, and the
        // owner's state replaces the confirmation.
        unawaited(_model.refresh());
        return true;
      },
    );
    if (!mounted) return;
    if (_appleNote != null) setState(() {});
    if (askApple) await _confirmWithApple(services);
  }

  /// Asks Apple for a fresh credential and deletes again with it; a
  /// cancel leaves the screen as it was.
  Future<void> _confirmWithApple(AppServices services) async {
    if (!services.settings.appleEnabled) {
      setState(() => _appleNote = appleUnavailable);
      return;
    }
    setState(() => _asking = true);
    AppleCredential? credential;
    try {
      credential = await services.providers.appleCredential();
    } on Object {
      if (mounted) {
        setState(() {
          _asking = false;
          _appleNote = appleFailed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _asking = false);
    if (credential == null) return;
    _apple = credential;
    await _delete();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _write]),
    builder: (context, _) => FieldLayout(
      title: 'Excluir conta',
      onBack: () => context.go(Routes.account),
      children: switch (_model.state) {
        FamilyReady(:final family) when family.role == FamilyRole.owner =>
          _owner(family),
        FamilyReady(:final family) => _confirmation(family),
        NoFamily() || EmailUnverified() => _confirmation(null),
        _ => familyPending(_model),
      },
    ),
  );

  /// What goes, a line of the list each, with the address set by [set]
  /// (to break at its safe points, or plain for assistive technology).
  List<String> _whatGoes(
    Family? family, [
    String Function(String) set = _plain,
  ]) {
    final email = _model.email;
    return [
      if (email == null)
        'Sua conta e as formas de entrar nela'
      else
        'Sua conta, com o e-⁠mail ${set(email)}, e as formas de entrar nela',
      'Os aparelhos conectados, que saem da conta',
      if (family != null)
        'Seu lugar na família, e com ele o acesso às crianças',
    ];
  }

  /// What stays, a paragraph each, with the titular's address set by
  /// [set] as in [_whatGoes].
  List<String> _whatStays(
    Family? family, [
    String Function(String) set = _plain,
  ]) {
    final titular = family?.members
        .where((m) => m.role == FamilyRole.owner)
        .map((m) => m.email)
        .firstOrNull;
    return [
      if (family != null)
        [
          family.minors.isEmpty
              ? 'A família continua'
              : 'A família e as crianças continuam',
          if (titular != null) ', com ${set(titular)} como titular',
          '.',
        ].join(),
      'O histórico da conta fica guardado sem seu e-⁠mail, sem ligação '
          'com você.',
      'Se quiser voltar depois, é só criar uma conta nova.',
    ];
  }

  List<Widget> _confirmation(Family? family) {
    final body = Theme.of(context).textTheme.bodyLarge;
    final idle = !_write.blocked && !_asking;
    return [
      Text('Excluir sua conta apaga na hora:', style: body),
      const SizedBox(height: Space.lg),
      for (final (shown, read) in _lines(_whatGoes, family))
        BulletItem(shown, semanticsLabel: read),
      // The list's last line keeps its own small gap; what stays starts
      // a group of its own.
      const SizedBox(height: Space.lg),
      for (final (shown, read) in _lines(_whatStays, family)) ...[
        Text(shown, style: body, semanticsLabel: read),
        const SizedBox(height: Space.md),
      ],
      const SizedBox(height: Space.md),
      DeclarationRow(
        text: _declaration,
        value: _declared,
        onChanged: idle ? (v) => setState(() => _declared = v) : null,
      ),
      const SizedBox(height: Space.xl),
      if (_write.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ],
      if (_appleNote case final note?) ...[
        ErrorNote(note),
        const SizedBox(height: Space.lg),
      ],
      PrimaryButton(
        label: 'Excluir minha conta',
        busy: _write.busy,
        onPressed: _declared && idle ? _delete : null,
      ),
      SubmitHint(declarationHint, visible: !_declared),
    ];
  }

  /// Each line of [list] as shown, its addresses set to break at their
  /// safe points, and as read, plain.
  List<(String, String)> _lines(
    List<String> Function(Family?, [String Function(String)]) list,
    Family? family,
  ) => [
    for (final (i, read) in list(family).indexed)
      (list(family, addressBreaks)[i], read),
  ];

  /// Suspension and pending terms both leave the invitations out of reach.
  bool get _cannotInvite => _model.suspended || !_model.termsAccepted;

  /// The owner's state: no deletion, the two ways to hand the family on
  /// (a transfer, or an invitation when no other adult is there yet).
  List<Widget> _owner(Family family) {
    final body = Theme.of(context).textTheme.bodyLarge;
    final others = family.members.any((m) => m.role != FamilyRole.owner);
    return [
      Text(
        others
            ? 'Você é titular da família, e ela precisa de alguém titular. '
                  'Para excluir sua conta, torne antes outro adulto titular, '
                  'ou exclua a família.'
            // A suspended account, or one waiting on the terms, cannot invite.
            : _cannotInvite
            ? 'Você é titular da família, e só você cuida dela. Para '
                  'excluir sua conta, exclua antes a família.'
            : 'Você é titular da família, e só você cuida dela. Para '
                  'excluir sua conta, exclua antes a família, ou convide '
                  'outro adulto e torne essa pessoa titular.',
        style: body,
      ),
      const SizedBox(height: Space.md),
      Text('Depois, volte aqui para excluir sua conta.', style: body),
      const SizedBox(height: Space.xl),
      // The way the copy names: hand the family to another adult, or
      // first invite one. An account that cannot invite is, alone,
      // offered only the family's deletion.
      if (others || !_cannotInvite) ...[
        Doors(
          children: [
            others
                ? DoorRow(
                    title: 'Tornar outro adulto titular',
                    onTap: () => context.go(Routes.adults),
                  )
                : DoorRow(
                    title: 'Convidar outro adulto',
                    onTap: () => context.go(Routes.invitations),
                  ),
          ],
        ),
        const SizedBox(height: Space.xxl),
      ],
      QuietAction(
        label: 'Excluir a família',
        destructive: true,
        onPressed: () => context.go(Routes.deleteFamily),
      ),
    ];
  }
}

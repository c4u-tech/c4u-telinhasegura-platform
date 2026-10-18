import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/check_email_screen.dart' show resentNotice;
import '../access/submission.dart';
import '../access/widgets.dart';
import '../auth/auth_api.dart';
import '../design/address.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family_model.dart';
import '../family/widgets.dart';
import '../legal/legal_links.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import '../staff/mfa.dart';
import 'mfa_words.dart';

/// The Aparelhos conectados door's line until the sessions are counted,
/// or when they cannot be.
const sessionsUnknown = 'Veja onde sua conta está conectada';

/// How many devices are signed in to the account: "1 aparelho",
/// "3 aparelhos". Never the child's linked devices.
String sessionsWords(int n) => n == 1 ? '1 aparelho' : '$n aparelhos';

/// `/conta`: the guardian's own account as its doors, holding no form
/// itself. It works with or without a
/// family and while the email waits for its confirmation, which shows
/// the verify line with resend above the doors.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _resend = Submission();
  late final FamilyModel _model;

  /// The sessions count; never read for a suspended account, whose
  /// session cannot list them (suspension screens): this index
  /// still builds beneath `/conta/dados` and `/conta/excluir`.
  Future<List<SessionSummary>>? _sessions;

  /// The factor's status, read only for a platform role holder:
  /// null until the roles say so.
  Future<MfaStatus>? _mfa;
  late final GoRouterDelegate _router;
  bool _started = false;

  /// Whether a task screen covers the index: coming back from one (the
  /// devices may have changed) counts the sessions again.
  late bool _away;
  bool _resent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final services = AppScope.of(context);
    _model = services.familyModel;
    // The account's email comes with the family's first read; arriving
    // here directly starts it. It notifies the router, so after this build.
    scheduleMicrotask(_model.load);
    _sessions = _readSessions();
    _model.addListener(_rolesRead);
    _rolesRead();
    _router = GoRouter.of(context).routerDelegate..addListener(_moved);
    _away = !_here;
  }

  bool get _here => _router.currentConfiguration.uri.path == Routes.account;

  // Under a task screen the door's builder may not listen yet: a failed
  // read stays the calm line, never an unhandled error.
  Future<List<SessionSummary>>? _readSessions() => _model.suspended
      ? null
      : (AppScope.of(context).auth.listSessions()..ignore());

  bool get _staff => (_model.roles?.isNotEmpty ?? false) && !_model.suspended;

  /// Reads the factor once the roles show one; no role, no MFA call, and
  /// none while suspended.
  void _rolesRead() {
    if (_mfa != null || !_staff) return;
    _mfa = _readMfa();
  }

  Future<MfaStatus> _readMfa() => AppScope.of(context).mfa.status()..ignore();

  void _moved() {
    final here = _here;
    if (here && _away) {
      setState(() {
        _sessions = _readSessions();
        if (_staff) _mfa = _readMfa();
      });
    }
    _away = !here;
  }

  @override
  void dispose() {
    _model.removeListener(_rolesRead);
    _router.removeListener(_moved);
    _resend.dispose();
    super.dispose();
  }

  Future<void> _resendLink(String email) async {
    final ok = await _resend.run(
      () => AppScope.of(context).auth.resendVerification(email),
    );
    if (ok) setState(() => _resent = true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _resend]),
    builder: (context, _) {
      final email = _model.email;
      return FieldLayout(
        title: 'Sua conta',
        onBack: () => context.go(Routes.home),
        children: [
          if (_model.state is EmailUnverified && email != null) ...[
            ..._verify(email),
            const SizedBox(height: Space.xl),
          ],
          Doors(
            children: [
              _door('E-⁠mail', email ?? '', Routes.accountEmail, address: true),
              _door(
                'Senha',
                'Trocar ou criar uma senha',
                Routes.accountPassword,
              ),
              if (_staff && _mfa != null)
                FutureBuilder(
                  future: _mfa,
                  builder: (context, read) => _door(
                    mfaTitle,
                    mfaDoorLine(
                          read.data,
                          _model.roles!,
                          clock.now(),
                          error: read.error,
                        ) ??
                        '',
                    Routes.accountMfa,
                  ),
                ),
              FutureBuilder(
                future: _sessions,
                builder: (context, read) =>
                    _door('Aparelhos conectados', switch (read.data) {
                      final sessions? => sessionsWords(sessions.length),
                      null => sessionsUnknown,
                    }, Routes.accountSessions),
              ),
              _door('Seus dados', 'Baixar uma cópia', Routes.accountData),
            ],
          ),
          const SizedBox(height: Space.xl),
          Doors(
            children: [
              _site(termsLabel, kTermsUrl),
              _site(privacyLabel, kPrivacyUrl),
            ],
          ),
          const SizedBox(height: Space.xxl),
          QuietAction(
            label: 'Excluir conta',
            destructive: true,
            onPressed: () => context.go(Routes.accountDelete),
          ),
        ],
      );
    },
  );

  /// A door named by [title], [line] under it (an email [address] set to
  /// break at its safe points), opening [path].
  DoorRow _door(
    String title,
    String line,
    String path, {
    bool address = false,
  }) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted);
    return DoorRow(
      title: title,
      semanticsLabel: line.isEmpty ? title : '$title, $line',
      onTap: () => context.go(path),
      child: switch (line) {
        '' => null,
        _ when address => AddressText(line, style: style),
        _ => Text(line, style: style),
      },
    );
  }

  /// A door named by [title] that opens [url] on the site, outside the
  /// app.
  DoorRow _site(String title, Uri url) =>
      DoorRow(title: title, onTap: () => AppScope.of(context).links.open(url));

  /// The family home's verify prompt, as a line: every door still opens,
  /// since fixing a typo'd email is part of the point.
  List<Widget> _verify(String email) {
    final text = Theme.of(context).textTheme;
    return [
      Text(
        'Para cadastrar as crianças e cuidar da sua família, confirme seu '
        'e-⁠mail. Procure a mensagem que enviamos para',
        style: text.bodyLarge,
      ),
      const SizedBox(height: Space.xs),
      AddressText(email, style: text.titleMedium),
      const SizedBox(height: Space.lg),
      if (_resend.message case final message?) ...[
        ErrorNote(message),
        const SizedBox(height: Space.lg),
      ] else if (_resent) ...[
        const Notice(resentNotice),
        const SizedBox(height: Space.lg),
      ],
      OutlinedButton(
        onPressed: _resend.blocked ? null : () => _resendLink(email),
        child: const Text('Reenviar e-⁠mail'),
      ),
    ];
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/reauth_write.dart';
import '../access/widgets.dart';
import '../auth/api_error.dart';
import '../curation/role_gate.dart';
import '../design/field_layout.dart';
import '../design/tokens.dart';
import '../family/confirm.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'accounts.dart';
import 'challenge.dart';
import 'factor_block.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// What a lookup sends for [text]: trimmed, a UUID in its canonical form as the account id, anything
/// else as the email. The server stays the judge (`validation`).
({String? email, String? accountId}) lookupKey(String text) {
  final key = text.trim();
  return _uuid.hasMatch(key)
      ? (email: null, accountId: key)
      : (email: key, accountId: null);
}

/// The search's one line.
const searchIntro =
    'A busca é por e-\u2060mail exato ou pelo código da conta. Cada busca '
    'fica na auditoria, com o motivo.';

/// On the field: nobody found (`account_not_found`).
const accountNotFound = 'Nenhuma conta com esse e-\u2060mail ou código.';

/// On the field: neither an email nor an id (`validation`).
const notAccountKey = 'Isso não é um e-\u2060mail nem um código de conta.';

/// The searches spent for the hour (`rate_limited`), in whole
/// minutes; the number and "min" never part across a line.
String searchesSpent(int minutes) =>
    'Você fez muitas buscas nesta hora. Tente de novo em $minutes\u00A0min.';

/// `/admin/contas` "Buscar uma conta":
/// one line, the field "E-mail ou código da conta", "Motivo" and the
/// primary "Buscar", waiting on both. A lookup goes through [ReauthWrite]
/// for the second factor, as every staff write; on `200` the sheet opens
/// with the answer, held in memory only, and the form empties
/// first, so coming back asks a new reason. A miss and a refused
/// key are said on the field; the hour's limit is the clay note counting
/// down in minutes ([FactorBlock]), "Buscar" waiting until it ends.
/// [notice] is what a sheet sent back ("Essa conta não existe mais.").
class AccountSearchScreen extends StatefulWidget {
  const AccountSearchScreen({super.key, this.notice});

  final String? notice;

  @override
  State<AccountSearchScreen> createState() => _AccountSearchScreenState();
}

class _AccountSearchScreenState extends State<AccountSearchScreen> {
  final _key = TextEditingController();
  final _reason = TextEditingController();
  final _block = FactorBlock();
  late final ReauthWrite _write;
  bool _started = false;

  /// The field's error, until the field changes.
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    _key.addListener(_keyChanged);
    _reason.addListener(() => setState(() {}));
  }

  String _lastKey = '';

  void _keyChanged() {
    if (_key.text == _lastKey) return;
    _lastKey = _key.text;
    setState(() => _fieldError = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _write = staffWrite(context);
    // Opened directly, the session's roles are read so the guard decides.
    scheduleMicrotask(AppScope.of(context).familyModel.load);
  }

  @override
  void dispose() {
    _key.dispose();
    _reason.dispose();
    _block.dispose();
    _write.dispose();
    super.dispose();
  }

  bool get _ready =>
      _key.text.trim().isNotEmpty &&
      validReason(_reason.text) &&
      !_write.blocked &&
      !_block.active;

  bool _onField(ApiError e) {
    if (takeLostRole(context, e)) return true;
    final words = switch (e.code) {
      'account_not_found' => accountNotFound,
      'validation' => notAccountKey,
      _ => null,
    };
    if (words == null) return false;
    setState(() => _fieldError = words);
    return true;
  }

  Future<void> _search() async {
    final api = AppScope.of(context).accounts;
    final key = lookupKey(_key.text);
    final reason = _reason.text.trim();
    AccountSheet? sheet;
    Duration? limited;
    setState(() => _fieldError = null);
    await _write.write(() async {
      try {
        sheet = await api.lookup(
          email: key.email,
          accountId: key.accountId,
          reason: reason,
        );
      } on ApiError catch (e) {
        if (e.code != 'rate_limited') rethrow;
        // Said in minutes here, not as the form's countdown.
        limited = e.retryAfter ?? const Duration(minutes: 1);
      }
    }, handle: _onField);
    if (!mounted) return;
    if (limited case final wait?) return _block.start(wait);
    final found = sheet;
    if (found == null) return;
    // Every lookup asks its own reason.
    _key.clear();
    _reason.clear();
    context.go(Routes.accountSheet(found.accountId), extra: found);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_write, _block]),
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final minutes = _block.minutes;
      return FieldLayout(
        title: 'Buscar uma conta',
        onBack: () => context.go(Routes.admin),
        children: [
          if (widget.notice case final notice?) ...[
            Notice(notice),
            const SizedBox(height: Space.xl),
          ],
          Text(searchIntro, style: text.bodyLarge),
          const SizedBox(height: Space.xl),
          if (minutes != null) ...[
            ErrorNote(searchesSpent(minutes)),
            const SizedBox(height: Space.xl),
          ] else if (_write.message case final message?) ...[
            ErrorNote(message),
            const SizedBox(height: Space.xl),
          ],
          TextField(
            controller: _key,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'E-\u2060mail ou código da conta',
              errorText: _fieldError,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: Space.lg),
          ReasonField(controller: _reason),
          const SizedBox(height: Space.xl),
          PrimaryButton(
            label: 'Buscar',
            busy: _write.busy,
            onPressed: _ready ? _search : null,
          ),
          SubmitHint(
            reasonHint,
            visible: !validReason(_reason.text),
            reserve: true,
          ),
        ],
      );
    },
  );
}

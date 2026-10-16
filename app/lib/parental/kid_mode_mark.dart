import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A local mark, "kid mode pending": the set of account ids that entered
/// kid mode on this device and have not given the PIN since. Each account
/// that enters kid mode is added; only that account, by giving its PIN (or
/// having no family or PIN to give), removes itself. While the set is not
/// empty, every sign-in on the device asks the PIN before the guardian
/// area opens.
abstract interface class KidModeMark {
  /// The marked account ids; empty when no mark is set.
  Future<Set<String>> read();
  Future<void> add(String accountId);
  Future<void> remove(String accountId);
}

/// Keeps the mark beside, but apart from, the session tokens, as a JSON
/// array of ids. A value that cannot be parsed counts as marked (fail
/// closed) and no account can remove it.
class SecureKidModeMark implements KidModeMark {
  SecureKidModeMark([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'ts.kid_mode_pending';
  static const _unreadable = '?';

  @override
  Future<Set<String>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return {};
    try {
      return {for (final id in jsonDecode(raw) as List<dynamic>) id as String};
    } on Object {
      return {_unreadable};
    }
  }

  @override
  Future<void> add(String accountId) async =>
      _write((await read())..add(accountId));

  @override
  Future<void> remove(String accountId) async =>
      _write((await read())..remove(accountId));

  Future<void> _write(Set<String> ids) => ids.isEmpty
      ? _storage.delete(key: _key)
      : ids.contains(_unreadable)
      ? Future<void>.value() // leave the unparsable value as it is
      : _storage.write(key: _key, value: jsonEncode(ids.toList()));
}

/// The default when none is given, and the test double.
class MemoryKidModeMark implements KidModeMark {
  MemoryKidModeMark([Iterable<String> ids = const []]) : _ids = {...ids};

  final Set<String> _ids;

  @override
  Future<Set<String>> read() async => {..._ids};

  @override
  Future<void> add(String accountId) async => _ids.add(accountId);

  @override
  Future<void> remove(String accountId) async => _ids.remove(accountId);
}

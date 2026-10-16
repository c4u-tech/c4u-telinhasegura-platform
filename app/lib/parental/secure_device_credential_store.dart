import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_credential_store.dart';

/// Keeps the device token in the Keychain / Android Keystore,
/// beside but apart from the guardian's session tokens.
class SecureDeviceCredentialStore implements DeviceCredentialStore {
  SecureDeviceCredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'ts.device_token';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

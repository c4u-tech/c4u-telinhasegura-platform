import 'package:telinha_segura/parental/device_credential_store.dart';

class MemoryDeviceCredentialStore implements DeviceCredentialStore {
  MemoryDeviceCredentialStore([this.token]);

  String? token;

  /// While set, reading the store fails, as a locked keychain does.
  bool unreadable = false;

  @override
  Future<String?> read() async {
    if (unreadable) throw StateError('storage');
    return token;
  }

  @override
  Future<void> write(String t) async => token = t;

  @override
  Future<void> clear() async => token = null;
}

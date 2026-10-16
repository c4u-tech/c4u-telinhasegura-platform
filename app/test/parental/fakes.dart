import 'package:telinha_segura/parental/device_credential_store.dart';

class MemoryDeviceCredentialStore implements DeviceCredentialStore {
  MemoryDeviceCredentialStore([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String t) async => token = t;

  @override
  Future<void> clear() async => token = null;
}

/// Where a linked child device keeps its device token. Android and iOS
/// only: on the web it would sit where any script can read it.
abstract interface class DeviceCredentialStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/secure_token_store.dart';
import 'package:telinha_segura/auth/token_store.dart';
import 'package:telinha_segura/parental/secure_device_credential_store.dart';

void main() {
  test('round-trips and clears the device token', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureDeviceCredentialStore();

    expect(await store.read(), isNull);
    await store.write('dev-token');
    expect(await store.read(), 'dev-token');
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('clearing it leaves a guardian session alone', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await SecureTokenStore().write(const Tokens(access: 'a', refresh: 'r'));
    await SecureDeviceCredentialStore().clear();
    expect((await SecureTokenStore().read())?.access, 'a');
  });
}

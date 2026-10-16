import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/secure_token_store.dart';
import 'package:telinha_segura/auth/token_store.dart';

void main() {
  test('round-trips and clears the tokens', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureTokenStore();

    expect(await store.read(), isNull);
    await store.write(const Tokens(access: 'a', refresh: 'r'));
    final read = await store.read();
    expect((read?.access, read?.refresh), ('a', 'r'));
    await store.clear();
    expect(await store.read(), isNull);
  });
}

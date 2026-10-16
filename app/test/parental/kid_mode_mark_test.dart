import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/secure_token_store.dart';
import 'package:telinha_segura/auth/token_store.dart';
import 'package:telinha_segura/parental/kid_mode_mark.dart';

void main() {
  test('round-trips, holds two accounts and removes one', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final mark = SecureKidModeMark();

    expect(await mark.read(), isEmpty);
    await mark.add('a1');
    expect(await SecureKidModeMark().read(), {'a1'});
    await mark.add('b1');
    await mark.add('b1');
    expect(await mark.read(), {'a1', 'b1'});
    await mark.remove('a1');
    expect(await mark.read(), {'b1'});
    await mark.remove('b1');
    expect(await mark.read(), isEmpty);
  });

  test('an unparsable value counts as marked and survives a remove', () async {
    FlutterSecureStorage.setMockInitialValues({
      'ts.kid_mode_pending': 'not json',
    });
    final mark = SecureKidModeMark();
    expect(await mark.read(), isNotEmpty);
    await mark.remove('a1');
    expect(await mark.read(), isNotEmpty);
  });

  test('removing it leaves a guardian session alone', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await SecureTokenStore().write(const Tokens(access: 'a', refresh: 'r'));
    await SecureKidModeMark().add('a1');
    await SecureKidModeMark().remove('a1');
    expect((await SecureTokenStore().read())?.access, 'a');
  });

  test('the memory mark behaves the same', () async {
    final mark = MemoryKidModeMark();
    expect(await mark.read(), isEmpty);
    await mark.add('a1');
    await mark.add('b1');
    await mark.remove('a1');
    expect(await mark.read(), {'b1'});
    await mark.remove('b1');
    expect(await mark.read(), isEmpty);
  });
}

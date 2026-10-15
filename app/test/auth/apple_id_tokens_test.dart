import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/auth/apple_id_tokens.dart';

const _channel = MethodChannel('com.aboutyou.dart_packages.sign_in_with_apple');

/// Answers Apple's sign-in on the plugin channel and records the state
/// each request sent; [echo] picks the state the answer carries.
List<String?> _fakeApple(String? Function(String? sent) echo) {
  final sent = <String?>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        final request = (call.arguments as List<dynamic>).single as Map;
        final state = request['state'] as String?;
        sent.add(state);
        return {
          'type': 'appleid',
          'authorizationCode': 'code',
          'identityToken': 'id-tok',
          'state': echo(state),
        };
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return sent;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppleIdTokens apple() => AppleIdTokens(
    servicesId: 'tech.coding4u.telinhasegura.web',
    redirectUri: Uri.parse('https://api.test/v1/oauth/apple/callback'),
  );

  test('every request carries a fresh random state', () async {
    final sent = _fakeApple((s) => s);

    expect(await apple().obtain(), 'id-tok');
    expect(await apple().obtain(), 'id-tok');

    expect(sent, hasLength(2));
    for (final s in sent) {
      expect(s, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    }
    expect(sent[0], isNot(sent[1]));
  });

  test('an answer carrying another state is refused', () async {
    _fakeApple((_) => 'forged');
    expect(apple().obtain(), throwsStateError);
  });

  test('Apple JS is prepared before the plugin is called', () async {
    final order = <String>[];
    _fakeApple((s) {
      order.add('plugin');
      return s;
    });
    final tokens = AppleIdTokens(
      servicesId: 'tech.coding4u.telinhasegura.web',
      redirectUri: Uri.parse('https://app.test'),
      prepare: () async => order.add('prepare'),
    );

    await tokens.obtain();

    expect(order, ['prepare', 'plugin']);
  });

  test('an answer without a state is accepted', () async {
    _fakeApple((_) => null);
    expect(await apple().obtain(), 'id-tok');
  });
}

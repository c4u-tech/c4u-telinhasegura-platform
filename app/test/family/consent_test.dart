import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/family/consent.dart';
import 'package:telinha_segura/family/family.dart';

void main() {
  test('the text carries the version the app sends', () {
    // The app never records consent against a text it did not show.
    expect(ConsentText.version, kConsentPolicyVersion);
  });
}

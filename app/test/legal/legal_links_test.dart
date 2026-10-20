import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/family/consent.dart';
import 'package:telinha_segura/legal/legal_links.dart';

void main() {
  test('the terms version equals the backend constant', () {
    // The app must never record an acceptance of pages it did not show.
    final source = File('../backend/internal/identity/terms.go')
        .readAsStringSync();
    final match = RegExp(r'TermsVersion = "([^"]+)"').firstMatch(source);
    expect(match?.group(1), kTermsVersion);
  });

  test('the links open the site pages', () {
    expect(kTermsUrl.toString(), 'https://telinhasegura.coding4u.tech/termos');
    expect(
      kPrivacyUrl.toString(),
      'https://telinhasegura.coding4u.tech/privacidade',
    );
    expect(
      kCurationUrl.toString(),
      'https://telinhasegura.coding4u.tech/curadoria',
    );
    expect(ConsentText.privacyUrl, kPrivacyUrl);
  });
}

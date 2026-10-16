import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/staff/account_search_screen.dart';

void main() {
  test('a UUID, trimmed and in either case, is sent as the account id', () {
    for (final text in [
      '0b6f3c4e-9a1d-4c2b-8e7f-1a2b3c4d5e6f',
      '  0B6F3C4E-9A1D-4C2B-8E7F-1A2B3C4D5E6F \n',
      '00000000-0000-0000-0000-000000000000',
    ]) {
      final key = lookupKey(text);
      expect(key.accountId, text.trim(), reason: text);
      expect(key.email, isNull, reason: text);
    }
  });

  test('anything else is sent, trimmed, as the email; the server judges '
      'it', () {
    for (final (text, email) in [
      (' bia@example.com ', 'bia@example.com'),
      ('0b6f3c4e9a1d4c2b8e7f1a2b3c4d5e6f', '0b6f3c4e9a1d4c2b8e7f1a2b3c4d5e6f'),
      (
        '0b6f3c4e-9a1d-4c2b-8e7f-1a2b3c4d5e6',
        '0b6f3c4e-9a1d-4c2b-8e7f-1a2b3c4d5e6',
      ),
      (
        '{0b6f3c4e-9a1d-4c2b-8e7f-1a2b3c4d5e6f}',
        '{0b6f3c4e-9a1d-4c2b-8e7f-1a2b3c4d5e6f}',
      ),
      (
        '0b6f3c4e-9a1d-4c2b-8e7f-1a2b3c4d5e6g',
        '0b6f3c4e-9a1d-4c2b-8e7f-1a2b3c4d5e6g',
      ),
      ('qualquer coisa', 'qualquer coisa'),
    ]) {
      final key = lookupKey(text);
      expect(key.email, email, reason: text);
      expect(key.accountId, isNull, reason: text);
    }
  });
}

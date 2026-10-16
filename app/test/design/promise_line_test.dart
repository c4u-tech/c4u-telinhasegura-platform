import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/field_layout.dart';

import '../access/harness.dart';
import '../catalog/fixtures.dart';
import '../family/fixtures.dart';

const wide = Size(1280, 800);

void main() {
  // Publishing takes approvals from curators of any role, so no screen
  // may promise that only other parents looked (2026-10-06).
  test('the one promise speaks of the whole curating community', () {
    expect(
      promiseLine,
      'Cada vídeo daqui passa pelo olhar de pais, cuidadores e profissionais '
      'antes de chegar a uma criança.',
    );
  });

  for (final (name, path, family) in [
    ('the entry', '/entrar', null),
    ('the family home', '/', ownerFamily),
    ('a child\'s catalogue', '/familia/videos/m1', threeChildren),
  ]) {
    testWidgets('$name carries it on its wide panel', (tester) async {
      final h = Harness(signedIn: family != null, api: catalogApi())
        ..family = family;
      await h.pump(tester, initial: path, size: wide);

      expect(find.text(promiseLine), findsOneWidget);
      expect(find.textContaining('outros pais'), findsNothing);
    });
  }
}

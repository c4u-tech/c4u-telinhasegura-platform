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

  for (final (name, path, signedIn) in [
    ('the entry', '/entrar', false),
    ('the first use, before a family', '/', true),
  ]) {
    testWidgets('$name carries it on its wide panel', (tester) async {
      final h = Harness(signedIn: signedIn, api: catalogApi())..family = null;
      await h.pump(tester, initial: path, size: wide);

      expect(find.byKey(FieldLayout.panelKey), findsOneWidget);
      expect(find.text(promiseLine), findsOneWidget);
      expect(find.textContaining('outros pais'), findsNothing);
    });
  }

  // Beside the navigation's rail, the rail is the field: lockup, head and
  // the destinations, no panel and so no promise to carry.
  for (final (name, path, family) in [
    ('the home', '/', ownerFamily),
    ('a child\'s catalogue', '/familia/videos/m1', threeChildren),
  ]) {
    testWidgets('$name, beside the rail, has no panel to carry it', (
      tester,
    ) async {
      final h = Harness(signedIn: true, api: catalogApi())..family = family;
      await h.pump(tester, initial: path, size: wide);

      expect(find.byKey(FieldLayout.panelKey), findsNothing);
      expect(find.text(promiseLine), findsNothing);
      expect(find.textContaining('outros pais'), findsNothing);
    });
  }
}

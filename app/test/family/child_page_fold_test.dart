import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/family/child_page.dart';

import '../access/harness.dart';
import '../catalog/fixtures.dart';
import '../store_screens/store_screens_test.dart' show loadFonts;
import 'child_page_test.dart' show liaFive, pageApi, phone;
import 'fixtures.dart';

void main() {
  // The fold depends on the real face's metrics, not the test font's.
  setUpAll(loadFonts);

  testWidgets('on a 412 × 915 phone the "Vídeos" title stands above the '
      'fold, so the page promises more below', (tester) async {
    late final Harness h;
    h = Harness(
      signedIn: true,
      api: pageApi(() => h, catalog: (_, _) => page(liaFive, packs: liaPacks)),
    )..family = familyWith([minorJson('m1', 'Lia')]);
    await h.pump(tester, initial: '/familia/criancas/m1', size: phone);

    final title = find.byWidgetPredicate(
      (w) => w is SectionTitle && w.title == 'Vídeos',
    );
    expect(tester.getBottomLeft(title).dy, lessThan(phone.height));
  });
}

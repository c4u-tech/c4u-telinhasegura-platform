import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telinha_segura/design/tokens.dart';
import 'package:telinha_segura/design/wordmark.dart';

void main() {
  testWidgets('the wordmark keeps its proportions at every size', (
    tester,
  ) async {
    for (final h in [
      WordmarkSizes.band,
      WordmarkSizes.rail,
      WordmarkSizes.hero,
    ]) {
      await tester.pumpWidget(Center(child: Wordmark(height: h)));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(Wordmark));
      expect(size.height, h);
      expect(size.width / size.height, closeTo(387.24 / 60, 0.05));
    }
  });
}

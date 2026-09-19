import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/terms_page.dart';
import 'package:quark/widgets/terms/terms_summary.dart';

/// #2027: the first thing a new owner read was a full legal document, with no
/// short statement of the three things that actually shape how they use a
/// Quark. The summary sits above the terms, and says it is a summary.
void main() {
  Future<void> pumpTerms(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TermsPage()));
    await tester.pumpAndSettle();
  }

  for (final (label, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('$label: the summary leads the page', (tester) async {
      await pumpTerms(tester, size);

      final summary = find.byKey(const ValueKey('terms_summary'));
      expect(summary, findsOneWidget);
      expect(
        tester.getRect(summary).top,
        lessThan(tester.getRect(find.text('Definitions')).top),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('it says it is not the agreement', (tester) async {
    await pumpTerms(tester, const Size(700, 1400));

    expect(find.text(kTermsSummaryDisclaimer), findsOneWidget);
    expect(find.text('In plain English'), findsOneWidget);
  });

  testWidgets('it makes the three points the terms make', (tester) async {
    await pumpTerms(tester, const Size(700, 1400));

    for (final point in kTermsSummaryPoints) {
      expect(find.text(point.headline), findsOneWidget);
    }
    // The full document is still there underneath it.
    expect(find.text('3. No Warranty'), findsOneWidget);
  });
}

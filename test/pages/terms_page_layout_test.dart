import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/terms_page.dart';
import 'package:quark/widgets/terms/agree_button.dart';

/// #2007: on a phone the terms stopped flush against the fixed I Agree bar,
/// which reads as text cut off rather than text that has ended — and the bar
/// had no surface of its own, so it looked like part of the page it was
/// covering.
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
    testWidgets('$label: the agree bar is always reachable', (tester) async {
      await pumpTerms(tester, size);

      expect(find.byType(AgreeButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label: the bar stands apart from the terms', (tester) async {
      await pumpTerms(tester, size);

      // The bar draws its own surface with a line above it, so the text
      // behind it cannot read as continuing underneath.
      final decorated = tester.widgetList<DecoratedBox>(
        find.ancestor(
          of: find.byType(AgreeButton),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        decorated.any(
          (d) => (d.decoration as BoxDecoration).border?.top.width != null,
        ),
        isTrue,
      );
    });
  }

  testWidgets('the last of the terms can be scrolled clear of the bar', (
    tester,
  ) async {
    await pumpTerms(tester, const Size(360, 640));

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -20000),
    );
    await tester.pumpAndSettle();

    final scrollBottom = tester
        .getRect(find.byType(SingleChildScrollView))
        .bottom;
    final lastText = tester.getRect(find.byType(Text).last).bottom;
    expect(lastText, lessThanOrEqualTo(scrollBottom));
    expect(tester.takeException(), isNull);
  });
}

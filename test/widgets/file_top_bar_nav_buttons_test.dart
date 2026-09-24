import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_top_bar/file_top_bar_nav_buttons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2314: the one arrow goes up a level, so its tooltip names the folder it
/// lands in rather than promising history.
void main() {
  Future<void> pumpButton(
    WidgetTester tester,
    String currentPath, {
    bool navEnabled = true,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.dark(),
      home: Scaffold(
        body: FileTopBarNavButtons(
          navEnabled: navEnabled,
          currentPath: currentPath,
          rootPath: '',
          onGoUp: () {},
        ),
      ),
    ),
  );

  testWidgets('names the parent folder', (tester) async {
    await pumpButton(tester, '/docs/reports');

    expect(find.byTooltip('Back to docs'), findsOneWidget);
  });

  testWidgets('names Files when the parent is the root', (tester) async {
    await pumpButton(tester, '/docs');

    expect(find.byTooltip('Back to Files'), findsOneWidget);
  });

  testWidgets('has no tooltip at the top, where it is disabled', (
    tester,
  ) async {
    await pumpButton(tester, '');

    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('has no tooltip while navigation is disabled', (tester) async {
    await pumpButton(tester, '/docs/reports', navEnabled: false);

    expect(find.byType(Tooltip), findsNothing);
  });
}

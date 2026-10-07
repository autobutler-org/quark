import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/route_resolution_loading_shell.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2607: the deep-link loading shell waits with a `QuarkLoader`, which
/// pulses under reduced motion, not a Material bar that sweeps regardless.
void main() {
  testWidgets('shows a pulsing loader under reduced motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: const Scaffold(
          body: RouteResolutionLoadingShell(path: 'Documents/report.pdf'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Opening file'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is ProgressIndicator), findsNothing);
  });

  // The loader is taller than the bar it replaced; a short pane scrolls the
  // shell instead of overflowing it.
  testWidgets('fits a short pane', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 150,
              child: RouteResolutionLoadingShell(path: 'Documents'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

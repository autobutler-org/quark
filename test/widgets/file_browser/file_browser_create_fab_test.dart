import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_browser_create_fab.dart';

Duration _fade(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).duration;

Future<void> _pump(WidgetTester tester, {bool visible = true}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: FileBrowserCreateFab(
            visible: visible,
            onPressed: () {},
          ),
        ),
      ),
    );

/// #2607: the create button's fade honors reduced motion.
void main() {
  testWidgets('fades in and out', (tester) async {
    await _pump(tester);
    expect(_fade(tester), greaterThan(Duration.zero));
  });

  testWidgets('shows and hides at once under reduced motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pump(tester);
    expect(_fade(tester), Duration.zero);

    await _pump(tester, visible: false);
    await tester.pump();
    final fade = find.descendant(
      of: find.byType(AnimatedOpacity),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, 0.0);
  });
}

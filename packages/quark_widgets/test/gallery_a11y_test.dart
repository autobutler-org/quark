import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The gallery's registry is the one place every exported widget is built
// with data. Its package depends on this one, so reaching it by path is what
// avoids a dependency cycle.
// ignore: avoid_relative_lib_imports
import '../examples/widget_gallery/lib/registry.dart';
import 'support/pump.dart';

/// Holds every gallery entry to the tap target guidelines (#2603, #2605,
/// #2939), the calendar's month, week and day among them.
///
/// The gallery renders every exported widget with fake data, so this one file
/// reaches widgets whose own test never shows the part that fails — a menu
/// button that only appears with a callback, a chevron that only appears with
/// children. It runs at the wide viewport only: the gallery lays several
/// variants side by side and is not built for a phone. Each widget's own test
/// covers the narrow viewport.
void main() {
  for (final entry in registry) {
    testWidgets('${entry.name} meets the tap target guidelines', (
      tester,
    ) async {
      await pumpAt(
        tester,
        SingleChildScrollView(
          child: Padding(
            // The guideline skips a target touching the screen's edge or a
            // scrollable's, so keep the entry clear of both.
            padding: const EdgeInsets.all(16),
            child: Builder(builder: (context) => entry.build(context, (_) {})),
          ),
        ),
      );
      await expectTapTargetGuidelines(tester);
    });
  }
}

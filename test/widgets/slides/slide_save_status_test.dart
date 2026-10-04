import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/slide_save_status.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' as tap;

/// The slide editor's save chip names each save state and saves only when
/// there is something to save (#1161).
void main() {
  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('each state reads and acts as it should ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      var saves = 0;
      for (final (state, tooltip, canSave) in [
        (SlideSaveState.saved, 'All changes saved', false),
        (SlideSaveState.dirty, 'Save now', true),
        (SlideSaveState.saving, 'Saving', false),
        (SlideSaveState.failed, "Couldn't save the presentation.", true),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
            home: Scaffold(
              body: Center(
                child: SlideSaveStatus(state: state, onSave: () => saves++),
              ),
            ),
          ),
        );
        expect(find.byTooltip(tooltip), findsOneWidget, reason: '$state');
        final before = saves;
        await tester.tap(find.byKey(const ValueKey('slide_editor_save')));
        expect(saves - before, canSave ? 1 : 0, reason: '$state');
      }
    });
  }
}

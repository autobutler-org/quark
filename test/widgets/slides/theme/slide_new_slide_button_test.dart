import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/theme/slide_new_slide_button.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;

/// The slide panel's split New slide action (#1163): a tap adds, a long
/// press or the chevron picks a layout.
void main() {
  late List<String> events;

  setUp(() => events = []);

  Future<void> pump(WidgetTester tester, Axis direction) => tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
      home: Scaffold(
        body: Center(
          child: SlideNewSlideButton(
            layouts: SlideMaster.standard.layouts,
            onAdd: () => events.add('add'),
            onAddWithLayout: (id) => events.add('add $id'),
            direction: direction,
          ),
        ),
      ),
    ),
  );

  Finder key(String k) => find.byKey(ValueKey(k));

  for (final (name, size, direction) in [
    ('narrow', tap.narrowViewport, Axis.vertical),
    ('wide', tap.wideViewport, Axis.horizontal),
  ]) {
    testWidgets('adds, or adds on a layout picked ($name)', (tester) async {
      tap.setViewport(tester, size);
      await pump(tester, direction);
      await tap.expectTapTargetGuidelines(tester);

      await tester.tap(key('slide_panel_add'));
      await tester.pumpAndSettle();

      await tester.longPress(key('slide_panel_add'));
      await tester.pumpAndSettle();
      await tester.tap(key('slide_panel_add_sectionHeader'));
      await tester.pumpAndSettle();

      await tester.tap(key('slide_panel_add_menu'));
      await tester.pumpAndSettle();
      expect(find.text('Two content'), findsOneWidget);
      await tester.tap(key('slide_panel_add_twoContent'));
      await tester.pumpAndSettle();

      expect(events, ['add', 'add sectionHeader', 'add twoContent']);
      expect(find.byTooltip('New slide with layout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

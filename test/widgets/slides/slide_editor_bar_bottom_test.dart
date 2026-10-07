import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/slide_editor_bar_bottom.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' as tap;
import '../../support/text_scale.dart';

/// The slide editor's zoom row: buttons on a wide window, a labeled menu on
/// a phone, each disabled at its end of the range (#1153).
void main() {
  late List<String> events;

  setUp(() => events = []);

  Future<void> pumpRow(
    WidgetTester tester, {
    bool canZoomIn = true,
    bool canZoomOut = true,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Deck'),
          bottom: SlideEditorBarBottom(
            position: 'Slide 2 of 5',
            zoomPercent: '125%',
            onZoomIn: canZoomIn ? () => events.add('in') : null,
            onZoomOut: canZoomOut ? () => events.add('out') : null,
            onFit: () => events.add('fit'),
          ),
        ),
      ),
    ),
  );

  testWidgets('a wide window zooms from the row\'s buttons', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    await pumpRow(tester);
    expect(find.text('Slide 2 of 5'), findsOneWidget);
    expect(find.text('125%'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byTooltip('Zoom out'), findsOneWidget);
    expect(find.byTooltip('Fit slide'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('slide_zoom_in')));
    await tester.tap(find.byKey(const ValueKey('slide_zoom_fit')));
    await tester.tap(find.byKey(const ValueKey('slide_zoom_out')));
    expect(events, ['in', 'fit', 'out']);
    expect(find.byKey(const ValueKey('app_bar_bottom_menu')), findsNothing);
    await tap.expectTapTargetGuidelines(tester);
  });

  testWidgets('a phone zooms from the Zoom menu', (tester) async {
    tap.setViewport(tester, tap.narrowViewport);
    await pumpRow(tester);
    expect(find.byKey(const ValueKey('slide_zoom_in')), findsNothing);
    for (final (item, event) in [
      ('slide_menu_zoom_in', 'in'),
      ('slide_menu_zoom_fit', 'fit'),
      ('slide_menu_zoom_out', 'out'),
    ]) {
      await tester.tap(find.byKey(const ValueKey('app_bar_bottom_menu')));
      await tester.pumpAndSettle();
      if (item == 'slide_menu_zoom_fit') {
        expect(find.text('Fit slide (125%)'), findsOneWidget);
      }
      await tester.tap(find.byKey(ValueKey(item)));
      await tester.pumpAndSettle();
      expect(events.last, event);
    }
    expect(tester.takeException(), isNull);
    await tap.expectTapTargetGuidelines(tester);
  });

  testWidgets('each end of the range disables its button', (tester) async {
    tap.setViewport(tester, tap.wideViewport);
    await pumpRow(tester, canZoomIn: false, canZoomOut: false);
    await tester.tap(find.byKey(const ValueKey('slide_zoom_in')));
    await tester.tap(find.byKey(const ValueKey('slide_zoom_out')));
    expect(events, isEmpty);
  });

  testLargeText('the row fits', (tester, size) async {
    await pumpRow(tester);
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });
}

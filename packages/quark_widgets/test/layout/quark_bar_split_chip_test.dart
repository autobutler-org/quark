import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// #3194: a plain tap goes to the default device, and the second action
/// chooses another: a ▾ segment on a wide screen, a long press on a phone.
void main() {
  const key = ValueKey('upload');
  const choose = ValueKey('upload_choose');

  late List<String> events;
  setUp(() => events = []);

  Widget chip({bool secondary = true, bool enabled = true}) => Center(
    child: QuarkBarSplitChip(
      key: key,
      icon: QuarkIcons.upload_rounded,
      label: 'Upload',
      onPressed: enabled ? () => events.add('plain') : null,
      onSecondaryPressed: secondary ? () => events.add('choose') : null,
    ),
  );

  testBothViewports('a tap runs the plain action, and the second action is '
      'a segment on a wide screen and a long press on a phone', (
    tester,
    size,
  ) async {
    await pumpAt(tester, chip(), size: size);
    final narrow = size == narrowViewport;

    expect(tester.takeException(), isNull);
    expect(find.byKey(choose), narrow ? findsNothing : findsOneWidget);

    await tester.tap(find.byIcon(QuarkIcons.upload_rounded));
    await tester.pump();
    if (narrow) {
      await tester.longPress(find.byIcon(QuarkIcons.upload_rounded));
    } else {
      expect(
        find.descendant(
          of: find.byKey(choose),
          matching: find.byTooltip('Choose device'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(choose));
    }
    await tester.pumpAndSettle();

    expect(events, ['plain', 'choose']);
  });

  testBothViewports('on a wide screen it is one control: two segments in one '
      'border, sharing a hairline, at the bar height', (tester, size) async {
    await pumpAt(tester, chip(), size: size);
    if (size == narrowViewport) {
      expect(find.byType(OutlinedButton), findsNothing);
      return;
    }

    expect(
      find.descendant(
        of: find.byType(QuarkBarSplitChip),
        matching: find.byType(QuarkBarIconButton),
      ),
      findsNothing,
    );
    final segments = find.descendant(
      of: find.byType(QuarkBarSplitChip),
      matching: find.byType(OutlinedButton),
    );
    expect(segments, findsNWidgets(2));
    final label = tester.getRect(segments.first);
    final caret = tester.getRect(segments.last);
    // The ▾ border lies over the label's end border: one line, not two.
    expect(caret.left, label.right - 1);
    expect(caret.height, label.height);
    expect(label.height, QuarkBarIconButton.tapTargetSize);
    // Inside the tap target, the visual is the bar height.
    expect(
      tester
          .getSize(
            find.descendant(
              of: segments.first,
              matching: find.byType(Material),
            ),
          )
          .height,
      QuarkBarIconButton.size,
    );
  });

  testLargeText('the two segments grow together', (tester, size) async {
    await pumpAt(tester, chip(), size: size);
    expect(tester.takeException(), isNull);
    if (size == narrowViewport) return;

    double visual(Finder segment) => tester
        .getSize(find.descendant(of: segment, matching: find.byType(Material)))
        .height;
    final segments = find.byType(OutlinedButton);
    expect(visual(segments.first), greaterThan(QuarkBarIconButton.size));
    expect(visual(segments.last), visual(segments.first));
  });

  testBothViewports('without a second action it is a plain chip: no segment '
      'and no long press', (tester, size) async {
    await pumpAt(tester, chip(secondary: false), size: size);

    expect(find.byKey(choose), findsNothing);
    expect(find.byIcon(QuarkIcons.expand_more), findsNothing);
    await tester.longPress(find.byIcon(QuarkIcons.upload_rounded));
    await tester.pumpAndSettle();

    expect(events, isNot(contains('choose')));
  });

  testBothViewports('disabled, neither action runs', (tester, size) async {
    await pumpAt(tester, chip(enabled: false), size: size);

    expect(find.byKey(choose), findsNothing);
    await tester.tap(find.byIcon(QuarkIcons.upload_rounded));
    await tester.longPress(find.byIcon(QuarkIcons.upload_rounded));
    await tester.pumpAndSettle();

    expect(events, isEmpty);
  });
}

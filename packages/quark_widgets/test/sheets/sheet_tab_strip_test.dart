import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The sheet tabs under the spreadsheet editor (#1745). Worth guarding: which
/// gesture selects and which opens the menu, which entries are disabled at
/// the edges, that every callback carries the right index, and that 64 tabs
/// fit a narrow phone.
void main() {
  final events = <String>[];

  setUp(events.clear);

  SheetTabStrip strip(List<String> names, {int selectedIndex = 0}) =>
      SheetTabStrip(
        tabNames: names,
        selectedIndex: selectedIndex,
        onSelect: (i) => events.add('select $i'),
        onAdd: () => events.add('add'),
        onRename: (i) => events.add('rename $i'),
        onDuplicate: (i) => events.add('duplicate $i'),
        onMoveLeft: (i) => events.add('move_left $i'),
        onMoveRight: (i) => events.add('move_right $i'),
        onDelete: (i) => events.add('delete $i'),
      );

  const three = ['Sheet 1', 'Budget', 'Notes'];

  Finder tab(int index) => find.byKey(ValueKey('sheet_tab_$index'));
  Finder entry(String action) => find.byKey(ValueKey('sheet_tab_menu_$action'));

  bool isEnabled(WidgetTester tester, String action) =>
      tester.widget<PopupMenuItem<VoidCallback>>(entry(action)).enabled;

  testBothViewports('shows the add button and one tab per sheet', (
    tester,
    size,
  ) async {
    await pumpAt(tester, strip(three), size: size);

    expect(find.byKey(const ValueKey('sheet_tab_add')), findsOneWidget);
    for (var i = 0; i < three.length; i++) {
      expect(tab(i), findsOneWidget);
      expect(find.text(three[i]), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testBothViewports('shows a single tab', (tester, size) async {
    await pumpAt(tester, strip(const ['Sheet 1']), size: size);

    expect(tab(0), findsOneWidget);
    expect(find.byKey(const ValueKey('sheet_tab_add')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('the add button calls onAdd', (tester, size) async {
    await pumpAt(tester, strip(three), size: size);

    await tester.tap(find.byKey(const ValueKey('sheet_tab_add')));

    expect(events, ['add']);
  });

  testBothViewports('tapping an unselected tab selects it', (
    tester,
    size,
  ) async {
    await pumpAt(tester, strip(three), size: size);

    await tester.tap(tab(1));
    await tester.pumpAndSettle();

    expect(events, ['select 1']);
    expect(entry('rename'), findsNothing);
  });

  testBothViewports('tapping the selected tab opens its menu', (
    tester,
    size,
  ) async {
    await pumpAt(tester, strip(three, selectedIndex: 1), size: size);

    await tester.tap(tab(1));
    await tester.pumpAndSettle();

    expect(events, isEmpty);
    for (final action in [
      'rename',
      'duplicate',
      'move_left',
      'move_right',
      'delete',
    ]) {
      expect(isEnabled(tester, action), isTrue, reason: action);
    }
    expect(tester.takeException(), isNull);
  });

  Finder menuButton(int index) =>
      find.byKey(ValueKey('sheet_tab_menu_button_$index'));

  testBothViewports('every tab has its own menu button', (tester, size) async {
    await pumpAt(tester, strip(three, selectedIndex: 1), size: size);

    for (var i = 0; i < three.length; i++) {
      expect(
        find.descendant(of: tab(i), matching: menuButton(i)),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(menuButton(i)).tooltip, 'Sheet options');
    }
    expect(find.byTooltip('Sheet options'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testBothViewports('every tab is 160 wide, button pinned to its right edge', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      strip(['A', 'Quarterly summary ' * 10], selectedIndex: 1),
      size: size,
    );
    await tester.ensureVisible(tab(0));
    await tester.pumpAndSettle();

    double gap(int i) =>
        tester.getTopRight(tab(i)).dx - tester.getTopRight(menuButton(i)).dx;

    for (final i in [0, 1]) {
      expect(tester.getSize(tab(i)).width, 160);
      expect(tester.getSize(menuButton(i)), const Size(24, 24));
    }
    expect(gap(0), gap(1));
    expect(tester.takeException(), isNull);
  });

  testBothViewports('a long name is cut short on one line', (
    tester,
    size,
  ) async {
    final long = 'Quarterly summary ' * 10;
    await pumpAt(tester, strip([long]), size: size);

    final label = tester.widget<Text>(find.text(long));
    expect(label.overflow, TextOverflow.ellipsis);
    expect(label.maxLines, 1);
    expect(
      tester.getTopRight(find.text(long)).dx,
      lessThanOrEqualTo(tester.getTopLeft(menuButton(0)).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('the selected tab menu button opens its menu', (
    tester,
    size,
  ) async {
    await pumpAt(tester, strip(three), size: size);

    await tester.tap(menuButton(0));
    await tester.pumpAndSettle();

    expect(isEnabled(tester, 'move_left'), isFalse);
    expect(isEnabled(tester, 'move_right'), isTrue);
    await tester.tap(entry('rename'));
    await tester.pumpAndSettle();

    expect(events, ['rename 0']);
  });

  testBothViewports('an unselected tab menu button opens its menu only', (
    tester,
    size,
  ) async {
    await pumpAt(tester, strip(three), size: size);
    await tester.ensureVisible(menuButton(2));
    await tester.pumpAndSettle();

    await tester.tap(menuButton(2));
    await tester.pumpAndSettle();

    expect(isEnabled(tester, 'move_right'), isFalse);
    expect(isEnabled(tester, 'move_left'), isTrue);
    await tester.tap(entry('duplicate'));
    await tester.pumpAndSettle();

    expect(events, ['duplicate 2']);
  });

  for (final (action, expected) in [
    ('rename', 'rename 2'),
    ('duplicate', 'duplicate 2'),
    ('move_left', 'move_left 2'),
    ('delete', 'delete 2'),
  ]) {
    testBothViewports('long-press then $action calls back with the index', (
      tester,
      size,
    ) async {
      await pumpAt(tester, strip(three), size: size);

      await tester.ensureVisible(tab(2));
      await tester.pumpAndSettle();
      await tester.longPress(tab(2));
      await tester.pumpAndSettle();
      await tester.tap(entry(action));
      await tester.pumpAndSettle();

      expect(events, [expected]);
      expect(entry(action), findsNothing);
    });
  }

  testBothViewports('move right calls back with the index', (
    tester,
    size,
  ) async {
    await pumpAt(tester, strip(three), size: size);

    await tester.tap(tab(0));
    await tester.pumpAndSettle();
    await tester.tap(entry('move_right'));
    await tester.pumpAndSettle();

    expect(events, ['move_right 0']);
  });

  testBothViewports('move left is disabled on the first tab', (
    tester,
    size,
  ) async {
    await pumpAt(tester, strip(three), size: size);

    await tester.tap(tab(0));
    await tester.pumpAndSettle();

    expect(isEnabled(tester, 'move_left'), isFalse);
    expect(isEnabled(tester, 'move_right'), isTrue);
    await tester.tap(entry('move_left'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(events, isEmpty);
  });

  testBothViewports('move right is disabled on the last tab', (
    tester,
    size,
  ) async {
    await pumpAt(tester, strip(three), size: size);

    await tester.ensureVisible(tab(2));
    await tester.pumpAndSettle();
    await tester.longPress(tab(2));
    await tester.pumpAndSettle();

    expect(isEnabled(tester, 'move_right'), isFalse);
    expect(isEnabled(tester, 'move_left'), isTrue);
  });

  testBothViewports('only one tab: delete and both moves are disabled', (
    tester,
    size,
  ) async {
    await pumpAt(tester, strip(const ['Sheet 1']), size: size);

    await tester.tap(tab(0));
    await tester.pumpAndSettle();

    expect(isEnabled(tester, 'delete'), isFalse);
    expect(isEnabled(tester, 'move_left'), isFalse);
    expect(isEnabled(tester, 'move_right'), isFalse);
    expect(isEnabled(tester, 'rename'), isTrue);
    expect(isEnabled(tester, 'duplicate'), isTrue);
  });

  testBothViewports('64 long-named tabs scroll, and the selected one shows', (
    tester,
    size,
  ) async {
    final names = [for (var i = 1; i <= 64; i++) 'Quarterly summary $i' * 3];
    await pumpAt(tester, strip(names, selectedIndex: 63), size: size);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tab(63).hitTestable(), findsOneWidget);
    expect(tab(0).hitTestable(), findsNothing);
  });

  testBothViewports('a newly selected off-screen tab is scrolled into view', (
    tester,
    size,
  ) async {
    final names = [for (var i = 1; i <= 64; i++) 'Sheet $i'];
    await pumpAt(tester, strip(names), size: size);
    expect(tab(40).hitTestable(), findsNothing);

    await pumpAt(tester, strip(names, selectedIndex: 40), size: size);
    await tester.pumpAndSettle();

    expect(tab(40).hitTestable(), findsOneWidget);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the selected tab text uses the tokens', (
      tester,
    ) async {
      await pumpAt(tester, strip(three), brightness: brightness);

      final selected = tester.widget<Text>(find.text('Sheet 1'));
      final other = tester.widget<Text>(find.text('Budget'));
      expect(selected.style?.color, tokens.foreground);
      expect(other.style?.color, tokens.mutedForeground);
    });
  }
}

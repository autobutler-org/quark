import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one menu row behind the account and group rows (#4103): a one-line
/// title, a muted subtitle, and a menu the button and a right-click share.
void main() {
  const rowKey = ValueKey('thing_row_a');
  const menuKey = ValueKey('thing_menu_a');

  List<QuarkMenuEntry> entriesFor(List<String> picked) => [
    QuarkMenuEntry(
      key: const ValueKey('thing_action_rename_a'),
      label: 'Rename',
      onSelected: () => picked.add('rename'),
    ),
    QuarkMenuEntry(
      key: const ValueKey('thing_action_delete_a'),
      label: 'Delete',
      destructive: true,
      onSelected: () => picked.add('delete'),
    ),
  ];

  testBothViewports('shows a long title and subtitle on one line each', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMenuRow(
        key: rowKey,
        menuKey: menuKey,
        leading: const Icon(QuarkIcons.group_outlined),
        title: 'Vacation ' * 30,
        subtitle: 'Members ' * 30,
        entries: entriesFor([]),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(rowKey), findsOneWidget);
    expect(find.byKey(menuKey), findsOneWidget);
    expect(find.byIcon(QuarkIcons.group_outlined), findsOneWidget);
    final subtitle = tester.widget<Text>(find.text('Members ' * 30));
    expect(subtitle.maxLines, 1);
    expect(subtitle.style?.color, QuarkTokens.dark.mutedForeground);
  });

  testWidgets('no subtitle leaves the line out', (tester) async {
    await pumpAt(tester, const QuarkMenuRow(key: rowKey, title: 'Alpha'));

    expect(tester.widget<ListTile>(find.byType(ListTile)).subtitle, isNull);
  });

  testWidgets('no entries leaves the menu out', (tester) async {
    await pumpAt(
      tester,
      const QuarkMenuRow(key: rowKey, menuKey: menuKey, title: 'Alpha'),
    );

    expect(find.byKey(menuKey), findsNothing);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testWidgets('busy shows a loader in place of the menu', (tester) async {
    final picked = <String>[];
    await pumpAt(
      tester,
      QuarkMenuRow(
        key: rowKey,
        menuKey: menuKey,
        title: 'Alpha',
        busy: true,
        entries: entriesFor(picked),
      ),
    );

    expect(find.byKey(menuKey), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(rowKey),
        matching: find.byType(QuarkLoader),
      ),
      findsOneWidget,
    );

    // The loader animates, so pump a fixed time rather than settle.
    await tester.tap(find.byKey(rowKey), buttons: kSecondaryMouseButton);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Rename'), findsNothing);
  });

  testWidgets('the button opens the menu and reports the pick', (tester) async {
    final picked = <String>[];
    await pumpAt(
      tester,
      QuarkMenuRow(
        key: rowKey,
        menuKey: menuKey,
        title: 'Alpha',
        menuTooltip: 'Actions for Alpha',
        entries: entriesFor(picked),
      ),
    );

    expect(
      tester.widget<QuarkMenuButton>(find.byKey(menuKey)).tooltip,
      'Actions for Alpha',
    );
    await tester.tap(find.byKey(menuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thing_action_rename_a')));
    await tester.pumpAndSettle();

    expect(picked, ['rename']);
  });

  testWidgets('a right-click opens the same menu', (tester) async {
    final picked = <String>[];
    await pumpAt(
      tester,
      QuarkMenuRow(
        key: rowKey,
        menuKey: menuKey,
        title: 'Alpha',
        entries: entriesFor(picked),
      ),
    );

    await tester.tap(find.byKey(rowKey), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thing_action_delete_a')));
    await tester.pumpAndSettle();

    expect(picked, ['delete']);
  });
}

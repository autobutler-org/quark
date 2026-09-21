import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  const shortcuts = [
    FileShortcut(id: 'my_files', label: 'My files', icon: Icons.home),
    FileShortcut(id: 'groups', label: 'Groups', icon: Icons.group),
    FileShortcut(id: 'all_files', label: 'All files', icon: Icons.folder),
  ];

  Future<void> pumpBar(
    WidgetTester tester, {
    Size size = wideViewport,
    List<FileShortcut> items = shortcuts,
    void Function(String id)? onSelected,
  }) => pumpAt(
    tester,
    FileShortcutBar(shortcuts: items, onSelected: (id) => onSelected?.call(id)),
    size: size,
  );

  testBothViewports('shows every shortcut it is given', (tester, size) async {
    await pumpBar(tester, size: size);

    for (final shortcut in shortcuts) {
      expect(
        find.byKey(ValueKey('file_shortcut_${shortcut.id}')),
        findsOneWidget,
        reason: '${shortcut.label} has to be reachable at ${size.width} px',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testBothViewports('hands back the id of the chip that was tapped', (
    tester,
    size,
  ) async {
    final tapped = <String>[];
    await pumpBar(tester, size: size, onSelected: tapped.add);

    await tester.tap(find.byKey(const ValueKey('file_shortcut_groups')));
    await tester.pump();

    expect(tapped, ['groups']);
  });

  testBothViewports('renders nothing when there are no shortcuts', (
    tester,
    size,
  ) async {
    await pumpBar(tester, size: size, items: const []);

    expect(find.byType(ActionChip), findsNothing);
    expect(
      tester.getSize(find.byType(FileShortcutBar)).height,
      0,
      reason: 'an empty bar must not take a strip of the page',
    );
  });

  testWidgets('scrolls sideways rather than overflowing a narrow phone', (
    tester,
  ) async {
    await pumpBar(
      tester,
      size: narrowViewport,
      items: const [
        FileShortcut(id: 'a', label: 'A very long shortcut', icon: Icons.home),
        FileShortcut(id: 'b', label: 'Another long one', icon: Icons.group),
        FileShortcut(id: 'c', label: 'And one more again', icon: Icons.folder),
      ],
    );

    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(FileShortcutBar), const Offset(-200, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('file_shortcut_c')), findsOneWidget);
  });
}

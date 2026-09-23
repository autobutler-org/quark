import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  Widget page(void Function(String) log) => Scaffold(
    appBar: QuarkAppBar(
      label: 'Files',
      icon: QuarkIcons.folder_outlined,
      bottom: QuarkAppBarBottom(
        lead: const Text('Home / Documents'),
        actions: [
          QuarkBarChip(
            key: const ValueKey('upload'),
            icon: QuarkIcons.upload_rounded,
            label: 'Upload',
            onPressed: () => log('upload'),
          ),
        ],
        menuChildren: [
          MenuItemButton(
            key: const ValueKey('grid'),
            onPressed: () => log('grid'),
            child: const Text('Grid'),
          ),
        ],
      ),
    ),
    body: const SizedBox.shrink(),
  );

  final menu = find.byKey(const ValueKey('app_bar_bottom_menu'));

  testWidgets('wide: the actions sit in the row', (tester) async {
    final log = <String>[];
    await pumpAt(tester, page(log.add), size: wideViewport, scaffold: false);

    expect(find.text('Home / Documents'), findsOneWidget);
    expect(menu, findsNothing);

    await tester.tap(find.byKey(const ValueKey('upload')));
    await tester.pump();

    expect(log, ['upload']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow: the actions collapse into a labeled menu', (
    tester,
  ) async {
    final log = <String>[];
    await pumpAt(tester, page(log.add), size: narrowViewport, scaffold: false);

    expect(find.byKey(const ValueKey('upload')), findsNothing);
    expect(
      find.descendant(of: menu, matching: find.text('Views')),
      findsOneWidget,
    );

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('grid')));
    await tester.pumpAndSettle();

    expect(log, ['grid']);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('adds its height to the bar', (tester, size) async {
    await pumpAt(tester, page((_) {}), size: size, scaffold: false);

    expect(
      tester.getSize(find.byType(AppBar)).height,
      kToolbarHeight + QuarkAppBarBottom.height,
    );
  });
}

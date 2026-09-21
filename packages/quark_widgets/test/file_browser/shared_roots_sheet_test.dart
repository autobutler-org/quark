import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  const items = [
    SharedRootItem(path: 'users/alice/Trip', name: 'Trip', owner: 'alice'),
    SharedRootItem(path: 'Family', name: 'Family', owner: 'carol'),
    SharedRootItem(path: 'Loose', name: 'Loose'),
  ];

  Future<void> pumpSheet(
    WidgetTester tester, {
    Size size = wideViewport,
    List<SharedRootItem> entries = items,
    void Function(String path)? onPicked,
  }) => pumpAt(
    tester,
    SharedRootsSheet(items: entries, onPicked: (path) => onPicked?.call(path)),
    size: size,
  );

  testBothViewports('names every share and who owns it', (tester, size) async {
    await pumpSheet(tester, size: size);

    for (final item in items) {
      expect(
        find.byKey(ValueKey('shared_root_${item.path}')),
        findsOneWidget,
        reason: '${item.name} has to be reachable at ${size.width} px',
      );
    }
    expect(find.text('Shared by alice'), findsOneWidget);
    expect(
      find.text('Shared by '),
      findsNothing,
      reason: 'an owner nobody could name is left unlabeled, not half-labeled',
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('hands back the path of the entry that was tapped', (
    tester,
    size,
  ) async {
    final picked = <String>[];
    await pumpSheet(tester, size: size, onPicked: picked.add);

    await tester.tap(find.byKey(const ValueKey('shared_root_Family')));
    await tester.pump();

    expect(picked, ['Family']);
  });

  testBothViewports('survives a name far wider than the sheet', (
    tester,
    size,
  ) async {
    await pumpSheet(
      tester,
      size: size,
      entries: const [
        SharedRootItem(
          path: 'users/alice/Long',
          name: 'A folder with a name nobody would ever type by hand at all',
          owner: 'a-username-that-goes-on-for-far-too-long-to-fit-on-one-line',
        ),
      ],
    );

    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/slides/slides_body.dart';

import '../../support/tap_target_guidelines.dart' as tap;

/// #1170: a presentation in the Slides list can be shared from its row menu.
void main() {
  final deck = FileNode(
    name: 'talk.qslide',
    size: 1,
    isDir: false,
    deviceName: 'Data',
    devicePath: '',
    deviceSerial: 'usb1',
    dirPath: 'decks/talk.qslide',
  );

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('Share hands back the row\'s file ($name)', (tester) async {
      tap.setViewport(tester, size);
      FileNode? shared;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlidesBody(
              loading: false,
              error: null,
              files: [deck],
              contentResults: const [],
              contentSearching: false,
              searchQuery: '',
              onRetry: () {},
              onCreateNew: () {},
              onOpen: (_) {},
              onShare: (n) => shared = n,
            ),
          ),
        ),
      );
      final path = deck.apiPath;
      await tester.tap(find.byKey(ValueKey('doc_sheet_menu_$path')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('doc_sheet_share_$path')));
      await tester.pumpAndSettle();
      expect(shared, same(deck));
      expect(tester.takeException(), isNull);
    });
  }
}

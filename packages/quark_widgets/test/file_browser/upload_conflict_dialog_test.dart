import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The choice in front of an upload whose name is taken (#2016).
void main() {
  Widget dialog(
    List<String> events, {
    bool showApplyToAll = false,
    bool applyToAll = false,
  }) => UploadConflictDialog(
    fileName: 'holiday.jpg',
    showApplyToAll: showApplyToAll,
    applyToAll: applyToAll,
    onApplyToAllChanged: (value) => events.add('applyToAll:$value'),
    onKeepBoth: () => events.add('keepBoth'),
    onReplace: () => events.add('replace'),
    onCancel: () => events.add('cancel'),
  );

  testBothViewports('names the file and offers all three ways out', (
    tester,
    size,
  ) async {
    await pumpAt(tester, dialog([]), size: size);

    expect(find.textContaining('holiday.jpg'), findsOneWidget);
    expect(find.text('Keep both'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('reports each choice through its own callback', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(tester, dialog(events), size: size);

    await tester.tap(find.byKey(const ValueKey('upload_conflict_cancel')));
    await tester.tap(find.byKey(const ValueKey('upload_conflict_replace')));
    await tester.tap(find.byKey(const ValueKey('upload_conflict_keep_both')));
    await tester.pump();

    expect(events, ['cancel', 'replace', 'keepBoth']);
  });

  testWidgets('offers the rest of the upload only when asked to', (
    tester,
  ) async {
    await pumpAt(tester, dialog([]));
    expect(
      find.byKey(const ValueKey('upload_conflict_apply_to_all')),
      findsNothing,
    );

    await pumpAt(tester, dialog([], showApplyToAll: true));
    expect(
      find.byKey(const ValueKey('upload_conflict_apply_to_all')),
      findsOneWidget,
    );
  });

  testBothViewports('ticking the offer reports the new value', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(tester, dialog(events, showApplyToAll: true), size: size);

    await tester.tap(
      find.byKey(const ValueKey('upload_conflict_apply_to_all')),
    );
    await tester.pump();

    expect(events, ['applyToAll:true']);
  });

  testBothViewports('survives a long file name', (tester, size) async {
    await pumpAt(
      tester,
      UploadConflictDialog(
        fileName: '${'a very long file name ' * 6}.jpg',
        showApplyToAll: true,
        onKeepBoth: () {},
        onReplace: () {},
        onCancel: () {},
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });
}

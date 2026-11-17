import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('shows a name that fits whole', (tester, size) async {
    await pumpAt(
      tester,
      const Center(child: FileNameText('notes.txt')),
      size: size,
    );

    expect(find.text('notes.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('cuts a long name short but keeps its extension', (
    tester,
    size,
  ) async {
    const name = 'Budget 2026 quarterly projections and revisions.qsheet';
    await pumpAt(
      tester,
      const Center(child: SizedBox(width: 160, child: FileNameText(name))),
      size: size,
    );

    // The extension is its own run, so the ellipsis lands before it.
    expect(find.text('.qsheet'), findsOneWidget);
    final stem = tester.widget<Text>(
      find.text('Budget 2026 quarterly projections and revisions'),
    );
    expect(stem.overflow, TextOverflow.ellipsis);
    expect(stem.maxLines, 1);
    expect(
      tester.getRect(find.text('.qsheet')).right,
      lessThanOrEqualTo(tester.getRect(find.byType(FileNameText)).right),
    );
    // A screen reader still hears the whole name, once.
    expect(find.bySemanticsLabel(name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cuts a long name with no extension short at the end', (
    tester,
  ) async {
    const name = 'A folder with a very long name that cannot fit';
    await pumpAt(
      tester,
      const Center(child: SizedBox(width: 120, child: FileNameText(name))),
    );

    final text = tester.widget<Text>(find.text(name));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });
}

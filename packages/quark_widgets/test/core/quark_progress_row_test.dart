import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one progress row behind `JobRow` and `UploadRow` (#4103): a name with
/// its actions, an optional muted line, a tabular status line, and a bar
/// while a fraction is set.
void main() {
  const rowKey = ValueKey('thing_row');

  testBothViewports('draws the name, note, status and bar', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkProgressRow(
        key: rowKey,
        title: 'vacation.mov',
        subtitle: '/Videos',
        status: 'Uploading · 4 MB of 10 MB',
        progress: 0.4,
        actions: [TextButton(onPressed: () {}, child: const Text('Cancel'))],
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('vacation.mov'), findsOneWidget);
    expect(find.text('/Videos'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.4);
    final status = tester.widget<Text>(find.text('Uploading · 4 MB of 10 MB'));
    expect(
      status.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testBothViewports('survives a long name and several actions', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkProgressRow(
        key: rowKey,
        title: 'Vacation ' * 40,
        subtitle: '/Photos/' * 40,
        status: 'Running · 40% · 1:02:03 · Attempt 3 · Quick copy',
        progress: 0.4,
        actions: [
          TextButton(onPressed: () {}, child: const Text('Cancel')),
          TextButton(onPressed: () {}, child: const Text('Retry')),
        ],
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('no progress hides the bar and no subtitle hides the note', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const QuarkProgressRow(key: rowKey, title: 'a.txt', status: 'Completed'),
    );

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.descendant(of: find.byKey(rowKey), matching: find.byType(Text)),
      findsNWidgets(2),
    );
  });

  testWidgets('clamps the fraction', (tester) async {
    await pumpAt(
      tester,
      const QuarkProgressRow(title: 'a', status: 'b', progress: 1.7),
    );

    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1.0,
    );
  });

  testWidgets('colors the status, muted by default', (tester) async {
    await pumpAt(
      tester,
      Column(
        children: [
          const QuarkProgressRow(title: 'a', status: 'Queued'),
          QuarkProgressRow(
            title: 'b',
            status: 'Failed',
            statusColor: QuarkTokens.dark.error,
          ),
        ],
      ),
    );

    Color? colorOf(String text) =>
        tester.widget<Text>(find.text(text)).style?.color;
    expect(colorOf('Queued'), QuarkTokens.dark.mutedForeground);
    expect(colorOf('Failed'), QuarkTokens.dark.error);
  });

  testWidgets('an action fires its own callback', (tester) async {
    var taps = 0;
    await pumpAt(
      tester,
      QuarkProgressRow(
        title: 'a',
        status: 'Running',
        actions: [
          TextButton(
            key: const ValueKey('thing_cancel'),
            onPressed: () => taps++,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('thing_cancel')));
    expect(taps, 1);
  });
}

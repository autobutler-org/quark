import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  const key = ValueKey('files_view_help');
  final longBody = List.filled(40, 'A long sentence that wraps.').join(' ');
  final topics = [
    const QuarkHelpTopic(
      heading: 'Unified',
      body: 'Every drive in one list.',
      icon: QuarkIcons.view_list_rounded,
    ),
    QuarkHelpTopic(heading: 'Per-device', body: longBody),
    QuarkHelpTopic(heading: 'Device tags', body: longBody),
  ];

  Widget button({String tooltip = 'Help'}) => Center(
    child: QuarkHelpButton(
      key: key,
      title: 'Unified and per-device views',
      topics: topics,
      tooltip: tooltip,
    ),
  );

  testWidgets('is an info bar button carrying its tooltip', (tester) async {
    await pumpAt(tester, button(tooltip: 'About these views'));

    final bar = tester.widget<QuarkBarIconButton>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(QuarkBarIconButton),
      ),
    );
    expect(bar.icon, QuarkIcons.info_outline);
    expect(bar.tooltip, 'About these views');
    expect(find.byTooltip('About these views'), findsOneWidget);
  });

  testWidgets('defaults its tooltip to Help', (tester) async {
    await pumpAt(tester, button());

    expect(find.byTooltip('Help'), findsOneWidget);
  });

  testBothViewports('tap opens the title and every topic without overflow', (
    tester,
    size,
  ) async {
    await pumpAt(tester, button(), size: size);
    expect(find.byType(QuarkHelpDialog), findsNothing);

    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();

    expect(find.byType(QuarkHelpDialog), findsOneWidget);
    expect(find.text('Unified and per-device views'), findsOneWidget);
    for (final (index, topic) in topics.indexed) {
      final row = find.byKey(ValueKey('quark_help_topic_$index'));
      await tester.ensureVisible(row);
      expect(
        find.descendant(of: row, matching: find.text(topic.heading)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(topic.body)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('quark_help_topic_0')),
        matching: find.byIcon(QuarkIcons.view_list_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });

  testWidgets('Close pops the dialog', (tester) async {
    await pumpAt(tester, button(), size: narrowViewport);
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('quark_help_close')));
    await tester.tap(find.byKey(const ValueKey('quark_help_close')));
    await tester.pumpAndSettle();

    expect(find.byType(QuarkHelpDialog), findsNothing);
    expect(find.byKey(key), findsOneWidget);
  });

  testWidgets('draws its icon and hands Close to onClose', (tester) async {
    var closed = 0;
    await pumpAt(
      tester,
      QuarkHelpDialog(
        title: 'Views',
        topics: topics,
        icon: QuarkIcons.lock_outline,
        onClose: () => closed++,
      ),
      size: narrowViewport,
    );

    expect(find.byIcon(QuarkIcons.lock_outline), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('quark_help_close')));
    await tester.tap(find.byKey(const ValueKey('quark_help_close')));
    await tester.pumpAndSettle();

    expect(closed, 1);
    expect(find.byType(QuarkHelpDialog), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Naming a chat channel and giving it a topic (#2422): the name is required
/// and leaves trimmed with the topic, and a refusal shows in the open dialog.
void main() {
  Future<List<(String, String)>> pumpDialog(
    WidgetTester tester, {
    Size size = wideViewport,
    String initialName = '',
    String initialTopic = '',
    bool isSubmitting = false,
    String? error,
  }) async {
    final submitted = <(String, String)>[];
    await pumpAt(
      tester,
      QuarkChannelDialog(
        title: 'New channel',
        submitLabel: 'Create',
        initialName: initialName,
        initialTopic: initialTopic,
        nameMaxLength: 64,
        topicMaxLength: 512,
        isSubmitting: isSubmitting,
        error: error,
        onSubmit: (name, topic) => submitted.add((name, topic)),
        onCancel: () {},
      ),
      size: size,
    );
    return submitted;
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  testBothViewports('hands back the name and topic trimmed', (
    tester,
    size,
  ) async {
    final submitted = await pumpDialog(tester, size: size);

    await tester.enterText(key('channel_dialog_name'), '  design ');
    await tester.enterText(key('channel_dialog_topic'), ' Mockups ');
    await tester.pump();
    await tester.tap(key('channel_dialog_submit'));

    expect(submitted, [('design', 'Mockups')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('never submits without a name', (tester) async {
    final submitted = await pumpDialog(tester);

    await tester.enterText(key('channel_dialog_topic'), 'Mockups');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(key('channel_dialog_submit')).onPressed,
      isNull,
    );
    expect(submitted, isEmpty);
  });

  testBothViewports(
    'starts from the channel for an edit, and shows a refusal',
    (tester, size) async {
      await pumpDialog(
        tester,
        size: size,
        initialName: 'design',
        initialTopic: 'Mockups',
        error: 'A channel with that name already exists. Pick another name.',
      );

      expect(find.text('design'), findsOneWidget);
      expect(find.text('Mockups'), findsOneWidget);
      expect(
        find.text(
          'A channel with that name already exists. Pick another name.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disables both buttons while saving', (tester) async {
    await pumpDialog(tester, initialName: 'design', isSubmitting: true);

    expect(
      tester.widget<FilledButton>(key('channel_dialog_submit')).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(key('channel_dialog_cancel')).onPressed,
      isNull,
    );
    expect(find.byType(QuarkLoader), findsOneWidget);
  });
}

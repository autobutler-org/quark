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

  // #2501: a new channel was private with no say in it and no word why.
  group('who can see it', () {
    Future<List<bool>> pumpChoice(
      WidgetTester tester, {
      Size size = wideViewport,
      bool isPrivate = true,
    }) async {
      final changes = <bool>[];
      await pumpAt(
        tester,
        QuarkChannelDialog(
          title: 'New channel',
          submitLabel: 'Create',
          isPrivate: isPrivate,
          onPrivacyChanged: changes.add,
          onSubmit: (_, _) {},
          onCancel: () {},
        ),
        size: size,
      );
      return changes;
    }

    testBothViewports('offers private and everyone, saying what each means', (
      tester,
      size,
    ) async {
      final changes = await pumpChoice(tester, size: size);

      expect(key('channel_dialog_private'), findsOneWidget);
      expect(key('channel_dialog_public'), findsOneWidget);
      expect(find.textContaining('Only people you add'), findsOneWidget);
      expect(
        find.textContaining('Every account on this Quark'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Semantics>(
              find
                  .descendant(
                    of: key('channel_dialog_private'),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .selected,
        isTrue,
      );

      await tester.ensureVisible(key('channel_dialog_public'));
      await tester.tap(key('channel_dialog_public'));
      expect(changes, [false]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picks private back from everyone', (tester) async {
      final changes = await pumpChoice(tester, isPrivate: false);

      await tester.tap(key('channel_dialog_private'));
      expect(changes, [true]);
    });

    testWidgets('an edit without the callback offers no choice', (
      tester,
    ) async {
      await pumpDialog(tester, initialName: 'design');

      expect(key('channel_dialog_private'), findsNothing);
      expect(key('channel_dialog_public'), findsNothing);
    });
  });
}

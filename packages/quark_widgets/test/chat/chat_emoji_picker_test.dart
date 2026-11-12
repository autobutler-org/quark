import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/src/chat/quark_message_list/chat_emoji_picker.dart';

import '../support/pump.dart';

/// The full reaction picker (#3452): every emoji, searched by name, and a
/// dismissal that chooses nothing.
void main() {
  const search = ValueKey('message_emoji_search_m1');
  const close = ValueKey('message_emoji_close_m1');

  testBothViewports('lays out the search and the first emoji', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      ChatEmojiPicker(messageId: 'm1', onPick: (_) {}, onClose: () {}),
      size: size,
    );

    expect(find.byKey(search), findsOneWidget);
    expect(find.byKey(const ValueKey('message_react_m1_😀')), findsOneWidget);
    expect(find.text('Smileys & Emotion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('search filters the catalog and a tap reports the emoji', (
    tester,
    size,
  ) async {
    String? picked;
    await pumpAt(
      tester,
      ChatEmojiPicker(
        messageId: 'm1',
        onPick: (emoji) => picked = emoji,
        onClose: () {},
      ),
      size: size,
    );

    await tester.enterText(find.byKey(search), 'party popper');
    await tester.pump();

    expect(find.byKey(const ValueKey('message_react_m1_🎉')), findsOneWidget);
    expect(find.byKey(const ValueKey('message_react_m1_😀')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('message_react_m1_🎉')));
    expect(picked, '🎉');
    expect(tester.takeException(), isNull);
  });

  bool searchFocused(WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(search),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode
      .hasFocus;

  testWidgets('the search waits for a tap on a touch screen (#4073)', (
    tester,
  ) async {
    await pumpAt(
      tester,
      ChatEmojiPicker(messageId: 'm1', onPick: (_) {}, onClose: () {}),
    );

    // Focused, it would raise the keyboard over the grid.
    expect(searchFocused(tester), isFalse);
  }, variant: TargetPlatformVariant.mobile());

  testWidgets('the search takes focus with a keyboard and pointer', (
    tester,
  ) async {
    await pumpAt(
      tester,
      ChatEmojiPicker(messageId: 'm1', onPick: (_) {}, onClose: () {}),
    );

    expect(searchFocused(tester), isTrue);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('a search with no name match says so', (tester) async {
    await pumpAt(
      tester,
      ChatEmojiPicker(messageId: 'm1', onPick: (_) {}, onClose: () {}),
    );

    await tester.enterText(find.byKey(search), 'no such emoji');
    await tester.pump();

    expect(find.text('No matches'), findsOneWidget);
    expect(find.byKey(const ValueKey('message_react_m1_😀')), findsNothing);
  });

  testWidgets('closing and dismissing the dialog choose nothing', (
    tester,
  ) async {
    String? result = 'unset';
    await pumpAt(
      tester,
      Builder(
        builder: (context) => FilledButton(
          onPressed: () {
            showChatEmojiPicker(context, messageId: 'm1').then((emoji) {
              result = emoji;
            });
          },
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatEmojiPicker), findsOneWidget);

    await tester.tap(find.byKey(close));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(ChatEmojiPicker), findsNothing);

    result = 'unset';
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(ChatEmojiPicker), findsNothing);
  });
}

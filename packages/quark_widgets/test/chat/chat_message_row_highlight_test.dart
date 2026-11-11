import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_widgets/src/chat/quark_message_list/chat_message_row.dart';
import 'package:quark_widgets/src/chat/quark_message_list/chat_message_row/chat_reaction_picker.dart';

import '../support/pump.dart';

/// The tint a message row wears while its menu is open (#3453): the touch
/// menu a long press opens (#4052), or the pointer menu of a right-click.
void main() {
  ChatMessageItem msg(String id) => ChatMessageItem(
    id: id,
    authorId: 'ada',
    authorName: 'Ada',
    sentAt: DateTime(2026, 9, 24, 9),
    body: 'hello $id',
  );

  Finder key(String k) => find.byKey(ValueKey(k));

  // The touch menu's copy of the row carries the same key, after the row.
  Color? tint(WidgetTester tester, String id) =>
      ((tester.widgetList<DecoratedBox>(key('message_menu_open_$id')).first)
                  .decoration
              as BoxDecoration)
          .color;

  Future<void> pumpRows(
    WidgetTester tester,
    Size size,
    List<String> reacted, {
    bool touch = true,
  }) => pumpAt(
    tester,
    Column(
      children: [
        for (final id in ['a', 'b'])
          ChatMessageRow(
            message: msg(id),
            avatar: null,
            onCopy: () {},
            onDelete: () {},
            onReact: reacted.add,
            touchMenu: touch,
          ),
      ],
    ),
    size: size,
  );

  testBothViewports('a long press tints the row until an action is chosen', (
    tester,
    size,
  ) async {
    await pumpRows(tester, size, []);
    expect(tint(tester, 'a'), isNull);

    await tester.longPress(key('message_body_a'));
    await tester.pumpAndSettle();
    final primary = QuarkTokens.of(
      tester.element(key('message_body_a').first),
    ).primary;
    expect(tint(tester, 'a'), isNotNull);
    expect(tint(tester, 'a')!.withValues(alpha: 1), primary);
    // Only the row the menu belongs to.
    expect(tint(tester, 'b'), isNull);

    await tester.tap(key('message_copy_a'));
    await tester.pumpAndSettle();
    expect(tint(tester, 'a'), isNull);
  });

  testBothViewports('dismissing the menu clears the tint', (
    tester,
    size,
  ) async {
    await pumpRows(tester, size, []);
    await tester.longPress(key('message_body_b'));
    await tester.pumpAndSettle();
    expect(tint(tester, 'b'), isNotNull);

    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.text('Copy text'), findsNothing);
    expect(tint(tester, 'b'), isNull);
  });

  testBothViewports('an emoji from the touch menu\'s bar clears the tint', (
    tester,
    size,
  ) async {
    final reacted = <String>[];
    await pumpRows(tester, size, reacted);
    await tester.longPress(key('message_body_a'));
    await tester.pumpAndSettle();
    final emoji = ChatReactionPicker.choices.first;
    expect(tint(tester, 'a'), isNotNull);

    await tester.tap(key('message_menu_react_a_$emoji'));
    await tester.pumpAndSettle();
    expect(reacted, [emoji]);
    expect(tint(tester, 'a'), isNull);
  });

  testBothViewports('Add reaction keeps the tint until the emoji menu closes', (
    tester,
    size,
  ) async {
    final reacted = <String>[];
    await pumpRows(tester, size, reacted, touch: false);
    await tester.tap(key('message_body_a'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(key('message_menu_react_a'));
    await tester.pumpAndSettle();
    final emoji = ChatReactionPicker.choices.first;
    expect(key('message_menu_react_a_$emoji'), findsOneWidget);
    expect(tint(tester, 'a'), isNotNull);

    await tester.tap(key('message_menu_react_a_$emoji'));
    await tester.pumpAndSettle();
    expect(reacted, [emoji]);
    expect(tint(tester, 'a'), isNull);
  });
}

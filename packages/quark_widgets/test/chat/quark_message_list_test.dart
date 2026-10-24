import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_widgets/src/chat/quark_message_list/chat_message_row.dart';
import 'package:quark_widgets/src/chat/quark_message_list/chat_message_row/chat_message_body.dart';
import 'package:quark_widgets/src/chat/quark_message_list/chat_message_row/chat_reaction_picker.dart';

import '../support/pump.dart';

/// A channel's message list (#2420): newest at the bottom, one header per run
/// of one author's messages, a rule per day, the special lines drawn their
/// own way, and older pages asked for rather than loaded.
void main() {
  final day1 = DateTime(2026, 9, 23, 9);
  final day2 = DateTime(2026, 9, 24, 9);

  ChatMessageItem msg(
    String id,
    DateTime at, {
    String author = 'ada',
    String body = 'hello',
    ChatMessageKind kind = ChatMessageKind.text,
    bool isUnverified = false,
  }) => ChatMessageItem(
    id: id,
    authorId: author,
    authorName: author == 'ada' ? 'Ada' : 'Bob',
    sentAt: at,
    body: body,
    kind: kind,
    isUnverified: isUnverified,
  );

  // Newest first.
  final messages = [
    msg(
      'm6',
      day2.add(const Duration(minutes: 20)),
      kind: ChatMessageKind.deleted,
    ),
    msg(
      'm5',
      day2.add(const Duration(minutes: 2)),
      author: 'bob',
      kind: ChatMessageKind.waitingForKey,
    ),
    msg(
      'm4',
      day2.add(const Duration(minutes: 1)),
      author: 'bob',
      body: 'morning',
    ),
    msg(
      'm3',
      day2,
      kind: ChatMessageKind.system,
      body: 'The channel key was rotated',
    ),
    msg('m2', day1.add(const Duration(minutes: 3)), body: 'still me'),
    msg('m1', day1, body: 'first'),
  ];

  Finder inMessage(String id, Finder matching) => find.descendant(
    of: find.byKey(ValueKey('message_$id')),
    matching: matching,
  );

  testWidgets('shows a spinner while the first page loads', (tester) async {
    await pumpAt(tester, const QuarkMessageList(messages: [], isLoading: true));

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
  });

  testWidgets('renders the error the caller handed it', (tester) async {
    await pumpAt(
      tester,
      const QuarkMessageList(messages: [], error: "Couldn't load messages."),
    );

    expect(find.text("Couldn't load messages."), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.text('No messages yet'), findsNothing);
  });

  testWidgets('retries the first page after it fails', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: const [],
        error: "Couldn't load messages.",
        onLoadOlder: () => events.add('load'),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('message_list_retry')));
    await tester.pump();

    expect(events, ['load']);
  });

  testWidgets('offers no retry when the caller cannot load', (tester) async {
    await pumpAt(
      tester,
      const QuarkMessageList(messages: [], error: "Couldn't load messages."),
    );

    expect(find.byKey(const ValueKey('message_list_retry')), findsNothing);
  });

  testWidgets('says so when the channel is empty', (tester) async {
    await pumpAt(tester, const QuarkMessageList(messages: []));

    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('draws the newest message at the bottom', (
    tester,
    size,
  ) async {
    await pumpAt(tester, QuarkMessageList(messages: messages), size: size);

    final newest = tester.getTopLeft(find.byKey(const ValueKey('message_m6')));
    final oldest = tester.getTopLeft(find.byKey(const ValueKey('message_m1')));
    expect(newest.dy, greaterThan(oldest.dy));
  });

  testWidgets('groups one author under one header and splits days', (
    tester,
  ) async {
    final avatars = <String>[];
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: messages,
        avatarBuilder: (context, userId) {
          avatars.add(userId);
          return const SizedBox();
        },
      ),
    );

    // m1 starts ada's run, m2 joins it. The system line m3 breaks runs, so
    // bob's m4 starts one that m5 joins, and ada's m6 starts another.
    expect(inMessage('m1', find.text('Ada')), findsOneWidget);
    expect(inMessage('m2', find.text('Ada')), findsNothing);
    expect(inMessage('m4', find.text('Bob')), findsOneWidget);
    expect(inMessage('m5', find.text('Bob')), findsNothing);
    expect(inMessage('m6', find.text('Ada')), findsOneWidget);
    expect(avatars..sort(), ['ada', 'ada', 'bob']);

    expect(inMessage('m1', find.text('September 23, 2026')), findsOneWidget);
    expect(inMessage('m3', find.text('September 24, 2026')), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(4));
    for (final message in messages) {
      expect(find.byKey(ValueKey('message_${message.id}')), findsOneWidget);
    }
  });

  testWidgets('starts a new header after five quiet minutes', (tester) async {
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [
          msg('b', day1.add(const Duration(minutes: 6))),
          msg('a', day1),
        ],
      ),
    );

    expect(inMessage('a', find.text('Ada')), findsOneWidget);
    expect(inMessage('b', find.text('Ada')), findsOneWidget);
  });

  // The 48dp reaction and menu buttons used to stand beside the header as
  // well as the body, so a header soaked up part of their height and the gap
  // under a group's first message came out smaller than the rest (#2890).
  testBothViewports('spaces one author\'s run of messages evenly', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [
          msg('c', day1.add(const Duration(minutes: 2)), body: 'three'),
          msg('b', day1.add(const Duration(minutes: 1)), body: 'two'),
          msg('a', day1, body: 'one'),
        ],
        onCopy: (_) {},
        onDelete: (_) {},
        onReact: (_, _) {},
      ),
      size: size,
    );

    Rect body(String id) =>
        tester.getRect(find.byKey(ValueKey('message_body_$id')));
    expect(inMessage('a', find.text('Ada')), findsOneWidget);
    expect(inMessage('b', find.text('Ada')), findsNothing);
    expect(body('b').top - body('a').bottom, body('c').top - body('b').bottom);
  });

  testBothViewports('draws the special lines their own way', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [
          msg(
            'u',
            day2.add(const Duration(minutes: 3)),
            kind: ChatMessageKind.system,
            body: 'Eve joined',
            isUnverified: true,
          ),
          ...messages,
        ],
      ),
      size: size,
    );

    expect(
      inMessage('m3', find.text('The channel key was rotated')),
      findsOneWidget,
    );
    expect(
      inMessage('m3', find.byIcon(QuarkIcons.info_outline)),
      findsOneWidget,
    );
    expect(
      inMessage('u', find.text('Eve joined (unverified)')),
      findsOneWidget,
    );
    expect(
      inMessage('u', find.byIcon(QuarkIcons.warning_amber)),
      findsOneWidget,
    );
    expect(
      inMessage('m5', find.text('Waiting for the key to read this message')),
      findsOneWidget,
    );
    expect(
      inMessage('m6', find.text('This message was deleted')),
      findsOneWidget,
    );
    expect(inMessage('m6', find.text('hello')), findsNothing);
  });

  testWidgets('unverified lines take the warning color', (tester) async {
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [
          msg(
            'u',
            day1,
            kind: ChatMessageKind.system,
            body: 'Eve joined',
            isUnverified: true,
          ),
        ],
      ),
    );

    final text = tester.widget<Text>(find.text('Eve joined (unverified)'));
    expect(text.style?.color, QuarkTokens.dark.warning);
  });

  testWidgets('asks for older messages from the load button', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: messages,
        hasMore: true,
        onLoadOlder: () => events.add('older'),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('message_list_load_older')));
    await tester.pump();

    expect(events, ['older']);
  });

  testWidgets('shows progress at the top while older ones load', (
    tester,
  ) async {
    await pumpAt(
      tester,
      QuarkMessageList(messages: messages, hasMore: true, isLoading: true),
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byKey(const ValueKey('message_list_load_older')), findsNothing);
    expect(find.byKey(const ValueKey('message_m1')), findsOneWidget);
  });

  testWidgets('retries older messages after an error', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: messages,
        hasMore: true,
        error: "Couldn't load older messages.",
        onLoadOlder: () => events.add('older'),
      ),
    );

    expect(find.text("Couldn't load older messages."), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('message_list_retry')));
    await tester.pump();

    expect(events, ['older']);
  });

  testWidgets('offers nothing older at the start of the channel', (
    tester,
  ) async {
    await pumpAt(tester, QuarkMessageList(messages: messages));

    expect(find.byKey(const ValueKey('message_list_load_older')), findsNothing);
    expect(find.byKey(const ValueKey('message_list_retry')), findsNothing);
  });

  testBothViewports('asks for older messages when scrolled near the top', (
    tester,
    size,
  ) async {
    var asked = 0;
    final many = [
      for (var i = 59; i >= 0; i--)
        msg(
          '$i',
          day1.add(Duration(minutes: i)),
          author: i.isEven ? 'ada' : 'bob',
        ),
    ];
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: many,
        hasMore: true,
        onLoadOlder: () => asked++,
      ),
      size: size,
    );
    expect(asked, 0);

    await tester.drag(find.byType(ListView), const Offset(0, 10000));
    await tester.pumpAndSettle();

    expect(asked, greaterThan(0));
  });

  group('message menu (#2631)', () {
    Finder key(String value) => find.byKey(ValueKey(value));

    /// Opens [id]'s menu from its button, says whether it offers Delete, and
    /// closes it again.
    Future<bool> offersDelete(WidgetTester tester, String id) async {
      if (key('message_menu_$id').evaluate().isEmpty) return false;
      await tester.tap(key('message_menu_$id'));
      await tester.pumpAndSettle();
      final offered = key('message_delete_$id').evaluate().isNotEmpty;
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      return offered;
    }

    testBothViewports('a long press opens the menu and Copy calls back', (
      tester,
      size,
    ) async {
      final copied = <String>[];
      await pumpAt(
        tester,
        QuarkMessageList(messages: messages, onCopy: copied.add),
        size: size,
      );
      expect(find.byType(SelectionArea), findsNothing);

      await tester.longPress(key('message_body_m4'));
      await tester.pumpAndSettle();
      expect(find.text('Copy text'), findsOneWidget);
      // Nobody passed onReact or onDelete.
      expect(find.text('Add reaction'), findsNothing);
      expect(find.text('Delete'), findsNothing);

      await tester.tap(key('message_copy_m4'));
      await tester.pumpAndSettle();
      expect(copied, ['m4']);
      expect(find.text('Copy text'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testBothViewports('a right-click opens the menu at the pointer', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageList(messages: messages, onCopy: (_) {}),
        size: size,
      );

      final at = tester.getCenter(key('message_body_m2'));
      await tester.tapAt(at, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      final entry = tester.getRect(key('message_copy_m2'));
      expect(entry.top, lessThan(at.dy + 40));
      expect(entry.bottom, greaterThan(at.dy - 40));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the menu button opens it from the keyboard', (tester) async {
      final copied = <String>[];
      await pumpAt(
        tester,
        QuarkMessageList(messages: messages, onCopy: copied.add),
      );

      Focus.of(
        tester.element(find.byIcon(QuarkIcons.more_vert).first),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Copy text'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(copied, hasLength(1));
    });

    testBothViewports('the menu and add-reaction glyphs share a center line', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: messages,
          permissions: ChatPermissionPreset.member.permissions,
          onReact: (_, _) {},
        ),
        size: size,
      );
      Finder glyph(String id) =>
          find.descendant(of: key(id), matching: find.byType(Icon));

      expect(
        tester.getSize(key('message_menu_m4')),
        tester.getSize(key('message_react_m4')),
      );
      expect(
        tester.getCenter(glyph('message_menu_m4')).dy,
        tester.getCenter(glyph('message_react_m4')).dy,
      );
    });

    testBothViewports('Add reaction offers the emoji and fires onReact', (
      tester,
      size,
    ) async {
      final events = <String>[];
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: messages,
          permissions: ChatPermissionPreset.member.permissions,
          onReact: (id, emoji) => events.add('$id $emoji'),
        ),
        size: size,
      );

      await tester.tap(key('message_menu_m4'));
      await tester.pumpAndSettle();
      await tester.tap(key('message_menu_react_m4'));
      await tester.pumpAndSettle();
      for (final emoji in ['👍', '❤️', '😂', '😮', '😢', '🎉']) {
        expect(key('message_menu_react_m4_$emoji'), findsOneWidget);
      }
      await tester.tap(key('message_menu_react_m4_🎉'));
      await tester.pumpAndSettle();

      expect(events, ['m4 🎉']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a viewer without add_reactions gets no Add reaction', (
      tester,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: messages,
          permissions: ChatPermissionPreset.viewer.permissions,
          onCopy: (_) {},
          onReact: (_, _) {},
        ),
      );

      await tester.tap(key('message_menu_m4'));
      await tester.pumpAndSettle();
      expect(find.text('Copy text'), findsOneWidget);
      expect(find.text('Add reaction'), findsNothing);
    });

    testWidgets('a moderator may delete any text message', (tester) async {
      final deleted = <String>[];
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: messages,
          permissions: ChatPermissionPreset.moderator.permissions,
          currentUserId: 'ada',
          onDelete: deleted.add,
        ),
      );

      expect(await offersDelete(tester, 'm2'), isTrue);
      expect(await offersDelete(tester, 'm4'), isTrue);

      await tester.tap(key('message_menu_m4'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Delete')).style?.color,
        QuarkTokens.dark.error,
      );
      await tester.tap(key('message_delete_m4'));
      await tester.pumpAndSettle();
      expect(deleted, ['m4']);
    });

    testWidgets('without delete_messages only the author may delete', (
      tester,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: messages,
          permissions: ChatPermissionPreset.member.permissions,
          currentUserId: 'ada',
          onCopy: (_) {},
          onDelete: (_) {},
        ),
      );

      expect(await offersDelete(tester, 'm2'), isTrue);
      expect(await offersDelete(tester, 'm4'), isFalse);
    });

    testWidgets('a viewer sees no delete on anyone else\'s message', (
      tester,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: messages,
          permissions: ChatPermissionPreset.viewer.permissions,
          currentUserId: 'cy',
          onCopy: (_) {},
          onDelete: (_) {},
        ),
      );

      expect(await offersDelete(tester, 'm2'), isFalse);
      expect(await offersDelete(tester, 'm4'), isFalse);
    });

    testBothViewports('deleted, waiting and system lines have no menu', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: messages,
          permissions: ChatPermissionPreset.owner.permissions,
          currentUserId: 'ada',
          onCopy: (_) {},
          onDelete: (_) {},
          onReact: (_, _) {},
        ),
        size: size,
      );

      for (final id in ['m3', 'm5', 'm6']) {
        expect(key('message_menu_$id'), findsNothing);
        final at = tester.getCenter(key('message_$id'));
        await tester.longPressAt(at);
        await tester.pumpAndSettle();
        await tester.tapAt(at, buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuItem<int>), findsNothing);
      }
      expect(key('message_menu_m4'), findsOneWidget);
    });

    group('on a desktop platform', () {
      const desktop = TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      });
      final linked = [
        msg('m1', day1, body: 'some words to select https://a.com/x'),
      ];

      Iterable<RenderParagraph> selected(WidgetTester tester) => tester
          .renderObjectList<RenderParagraph>(
            find.descendant(
              of: key('message_body_m1'),
              matching: find.byType(RichText),
            ),
          )
          .where((paragraph) => paragraph.selections.isNotEmpty);

      testWidgets('dragging the mouse selects message text', (tester) async {
        await pumpAt(
          tester,
          QuarkMessageList(messages: linked, onCopy: (_) {}),
        );
        expect(selected(tester), isEmpty);

        final body = tester.getRect(key('message_body_m1'));
        final gesture = await tester.startGesture(
          body.centerLeft + const Offset(2, 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveTo(body.centerLeft + const Offset(90, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        final selection = selected(tester).single.selections.single;
        printOnFailure('$selection');
        expect(selection.isCollapsed, isFalse);
        // The drag was the selection's: it opened nothing.
        expect(find.byType(PopupMenuItem<int>), findsNothing);
      }, variant: desktop);

      testWidgets('a right-click opens the menu, not a toolbar', (
        tester,
      ) async {
        final copied = <String>[];
        await pumpAt(
          tester,
          QuarkMessageList(messages: linked, onCopy: copied.add),
        );

        await tester.tap(
          key('message_body_m1'),
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);

        await tester.tap(key('message_copy_m1'));
        await tester.pumpAndSettle();
        expect(copied, ['m1']);
      }, variant: desktop);

      testWidgets('a long press is not the menu\'s', (tester) async {
        await pumpAt(
          tester,
          QuarkMessageList(messages: linked, onCopy: (_) {}),
        );

        await tester.longPress(key('message_body_m1'));
        await tester.pumpAndSettle();

        expect(find.byType(PopupMenuItem<int>), findsNothing);
        expect(key('message_menu_m1'), findsOneWidget);
      }, variant: desktop);

      testWidgets('a link still opens inside the selection area', (
        tester,
      ) async {
        final opened = <Uri>[];
        await pumpAt(
          tester,
          QuarkMessageList(messages: linked, onOpenLink: opened.add),
        );
        expect(find.byType(SelectionArea), findsOneWidget);

        await tester.tapOnText(find.textRange.ofSubstring('https://a.com/x'));
        await tester.pump();

        expect(opened, [Uri.parse('https://a.com/x')]);
      }, variant: desktop);
    });
  });

  testBothViewports('a delegated manager gets the not-a-member pane', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: messages,
        isLoading: true,
        permissions: const {ChatPermission.manageMembers},
        currentUserId: 'ada',
        onDelete: (_) {},
      ),
      size: size,
    );

    expect(
      find.byKey(const ValueKey('message_list_not_member')),
      findsOneWidget,
    );
    expect(find.text(QuarkMessageList.notMemberText), findsOneWidget);
    expect(find.byKey(const ValueKey('message_m1')), findsNothing);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.text('Waiting for the key to read this message'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('survives a thousand messages and unbroken words', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [
          for (var i = 999; i >= 0; i--)
            msg(
              '$i',
              day1.add(Duration(minutes: i * 3)),
              author: i % 3 == 0 ? 'ada' : 'bob',
              body: i.isEven ? 'x' * 500 : 'word ' * 80,
            ),
        ],
        permissions: ChatPermissionPreset.owner.permissions,
        onDelete: (_) {},
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });

  group('reactions (#2426)', () {
    final reacted = [
      ChatMessageItem(
        id: 'r2',
        authorId: 'bob',
        authorName: 'Bob',
        sentAt: day2,
        kind: ChatMessageKind.deleted,
        reactions: const [ChatReactionItem(emoji: '🎉', count: 1)],
      ),
      ChatMessageItem(
        id: 'r1',
        authorId: 'ada',
        authorName: 'Ada',
        sentAt: day1,
        body: 'lunch?',
        reactions: const [
          ChatReactionItem(emoji: '👍', count: 3, reactedByMe: true),
          ChatReactionItem(emoji: '😂', count: 1),
        ],
      ),
    ];

    testBothViewports('shows each emoji with its count', (tester, size) async {
      await pumpAt(tester, QuarkMessageList(messages: reacted), size: size);

      expect(inMessage('r1', find.text('👍 3')), findsOneWidget);
      expect(inMessage('r1', find.text('😂 1')), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('message_reaction_r1_👍')),
        ),
        matchesSemantics(
          label: '👍 3, including you',
          isSelected: true,
          hasSelectedState: true,
        ),
      );
      // A deleted message draws none, and no picker without onReact.
      expect(inMessage('r2', find.text('🎉 1')), findsNothing);
      expect(find.byKey(const ValueKey('message_react_r1')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testBothViewports('tapping a chip or picking an emoji fires onReact', (
      tester,
      size,
    ) async {
      final events = <String>[];
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: reacted,
          permissions: ChatPermissionPreset.member.permissions,
          onReact: (id, emoji) => events.add('$id $emoji'),
        ),
        size: size,
      );

      await tester.tap(find.byKey(const ValueKey('message_reaction_r1_👍')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('message_react_r1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('message_react_r1_🎉')));
      await tester.pump();

      expect(events, ['r1 👍', 'r1 🎉']);
      expect(find.byKey(const ValueKey('message_react_r2')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testBothViewports('a chip is a 48dp button a screen reader can press', (
      tester,
      size,
    ) async {
      final events = <String>[];
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: reacted,
          permissions: ChatPermissionPreset.member.permissions,
          onReact: (id, emoji) => events.add('$id $emoji'),
        ),
        size: size,
      );
      final handle = tester.ensureSemantics();

      final chip = find.byKey(const ValueKey('message_reaction_r1_😂'));
      final node = tester.getSemantics(chip);
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.rect.width, greaterThanOrEqualTo(48));
      expect(node.rect.height, greaterThanOrEqualTo(48));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      // A tap just below the drawn chip, in its touch target, lands too.
      await tester.tapAt(tester.getBottomLeft(chip) + const Offset(4, 4));
      expect(events, ['r1 😂', 'r1 😂']);
      handle.dispose();
      await expectTapTargetGuidelines(tester);
    });

    testWidgets('a viewer without add_reactions only sees them', (
      tester,
    ) async {
      final events = <String>[];
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: reacted,
          permissions: ChatPermissionPreset.viewer.permissions,
          onReact: (id, emoji) => events.add('$id $emoji'),
        ),
      );

      expect(find.byKey(const ValueKey('message_react_r1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('message_reaction_r1_👍')));
      await tester.pump();
      expect(events, isEmpty);
    });

    testBothViewports('the picker opens without animating', (
      tester,
      size,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpAt(
        tester,
        QuarkMessageList(messages: reacted, onReact: (_, _) {}),
        size: size,
      );

      await tester.tap(find.byKey(const ValueKey('message_react_r1')));
      await tester.pump();

      // Fully open on the first frame: the rect doesn't move once the ink
      // ripple and everything else settle.
      final item = find.byKey(const ValueKey('message_react_r1_👍'));
      final first = tester.getRect(item);
      await tester.pumpAndSettle();
      expect(tester.getRect(item), first);
    });
  });

  group('links (#2630)', () {
    List<String> urls(String text) => [
      for (final link in ChatMessageBody.linksIn(text)) link.uri.toString(),
    ];
    List<String> shown(String text) => [
      for (final link in ChatMessageBody.linksIn(text))
        text.substring(link.start, link.end),
    ];

    test('finds http, https and www addresses', () {
      expect(urls('see http://a.com/x'), ['http://a.com/x']);
      expect(urls('HTTPS://A.com/Path?q=1#f'), ['https://a.com/Path?q=1#f']);
      expect(urls('http://localhost:8080/files'), [
        'http://localhost:8080/files',
      ]);

      // www. opens as https, and is shown as written.
      expect(urls('go to www.example.org now'), ['https://www.example.org']);
      expect(shown('go to www.example.org now'), ['www.example.org']);
    });

    test('finds every address in one message', () {
      const text = 'first https://a.com then www.b.org\nand http://c.net/x';
      expect(urls(text), [
        'https://a.com',
        'https://www.b.org',
        'http://c.net/x',
      ]);
      expect(shown(text), ['https://a.com', 'www.b.org', 'http://c.net/x']);
    });

    test('leaves sentence punctuation and wrapping brackets out', () {
      expect(shown('Read https://a.com/x.'), ['https://a.com/x']);
      expect(shown('https://a.com/x, then lunch'), ['https://a.com/x']);
      expect(shown('really https://a.com/x?!'), ['https://a.com/x']);
      expect(shown('"https://a.com/x"'), ['https://a.com/x']);
      expect(shown('(see https://a.com/x)'), ['https://a.com/x']);
      expect(shown('(see https://a.com/x).'), ['https://a.com/x']);
      expect(shown('[https://a.com/x]'), ['https://a.com/x']);
      expect(shown('https://en.wikipedia.org/wiki/Foo_(bar)'), [
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      ]);
      expect(shown('(https://en.wikipedia.org/wiki/Foo_(bar))'), [
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      ]);
    });

    test('everything else is not a link', () {
      for (final text in [
        '',
        'no address here',
        'v1.2.3',
        'report.pdf',
        'foo.com',
        'mailto:ada@example.com',
        'ada@www.example.com',
        'javascript:alert(1)',
        'ftp://a.com/x',
        'file:///etc/passwd',
        'http://',
        'https://.',
        'www.',
        'www',
        '3www.example.com',
        'xhttp://a.com',
      ]) {
        expect(ChatMessageBody.linksIn(text), isEmpty, reason: text);
      }
    });

    const first = 'https://a.com/x';
    const second = 'www.b.org';
    final linked = [
      msg('l1', day1, body: 'see $first, or $second.\nsecond line'),
    ];

    TextSpan spanOf(WidgetTester tester, String text) {
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(const ValueKey('message_body_l1')),
          matching: find.byType(RichText),
        ),
      );
      TextSpan? found;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == text) found = span;
        return found == null;
      });
      return found!;
    }

    for (final (label, brightness, tokens) in [
      ('dark', Brightness.dark, QuarkTokens.dark),
      ('light', Brightness.light, QuarkTokens.light),
    ]) {
      testWidgets('$label: a link takes the primary color and an underline', (
        tester,
      ) async {
        await pumpAt(
          tester,
          QuarkMessageList(messages: linked, onOpenLink: (_) {}),
          brightness: brightness,
        );

        for (final url in [first, second]) {
          final span = spanOf(tester, url);
          expect(span.style?.color, tokens.primary);
          expect(span.style?.decoration, TextDecoration.underline);
          expect(span.recognizer, isNotNull);
        }
        // The words around a link stay as written, in the body's own style.
        expect(spanOf(tester, 'see ').style, isNull);
        expect(spanOf(tester, 'see ').recognizer, isNull);
        expect(
          find.text('see $first, or $second.\nsecond line'),
          findsOneWidget,
        );
      });
    }

    testBothViewports('tapping a link fires onOpenLink with its address', (
      tester,
      size,
    ) async {
      final opened = <Uri>[];
      await pumpAt(
        tester,
        QuarkMessageList(messages: linked, onOpenLink: opened.add),
        size: size,
      );

      await tester.tapOnText(find.textRange.ofSubstring(first));
      await tester.pump();
      expect(opened, [Uri.parse('https://a.com/x')]);

      await tester.tapOnText(find.textRange.ofSubstring(second));
      await tester.pump();
      expect(opened, [
        Uri.parse('https://a.com/x'),
        Uri.parse('https://www.b.org'),
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a link follows the message when its text changes', (
      tester,
    ) async {
      final opened = <Uri>[];
      await pumpAt(
        tester,
        QuarkMessageList(messages: linked, onOpenLink: opened.add),
      );
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: [msg('l1', day1, body: 'now http://c.net')],
          onOpenLink: opened.add,
        ),
      );

      await tester.tapOnText(find.textRange.ofSubstring('http://c.net'));
      await tester.pump();
      expect(opened, [Uri.parse('http://c.net')]);
    });

    testBothViewports('draws no link the caller cannot open', (
      tester,
      size,
    ) async {
      await pumpAt(tester, QuarkMessageList(messages: linked), size: size);

      final body = find.byKey(const ValueKey('message_body_l1'));
      final rich = tester.widget<RichText>(
        find.descendant(of: body, matching: find.byType(RichText)),
      );
      rich.text.visitChildren((span) {
        expect((span as TextSpan).recognizer, isNull);
        expect(span.style?.decoration, isNot(TextDecoration.underline));
        return true;
      });
      expect(find.text('see $first, or $second.\nsecond line'), findsOneWidget);
    });

    testBothViewports('an unverified message keeps its address plain', (
      tester,
      size,
    ) async {
      final opened = <Uri>[];
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: [msg('l1', day1, body: 'see $first', isUnverified: true)],
          onOpenLink: opened.add,
        ),
        size: size,
      );

      final text = tester.widget<Text>(find.text('see $first'));
      expect(text.textSpan, isNull);
      expect(text.style?.color, QuarkTokens.dark.warning);
      await tester.tap(find.byKey(const ValueKey('message_body_l1')));
      await tester.pump();
      expect(opened, isEmpty);
    });

    testBothViewports('a system line keeps its address plain', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: [
            msg('l1', day1, body: 'see $first', kind: ChatMessageKind.system),
          ],
          onOpenLink: (_) {},
        ),
        size: size,
      );

      expect(find.byKey(const ValueKey('message_body_l1')), findsNothing);
      expect(tester.widget<Text>(find.text('see $first')).textSpan, isNull);
    });

    testBothViewports('long lines and an unbroken address still fit', (
      tester,
      size,
    ) async {
      final long = 'https://a.com/${'segment-' * 80}end';
      final opened = <Uri>[];
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: [
            msg('l2', day1.add(const Duration(minutes: 1)), body: long),
            msg(
              'l1',
              day1,
              body: 'one\ntwo $first\n\nthree ${'word ' * 60}$second',
            ),
          ],
          permissions: ChatPermissionPreset.owner.permissions,
          onDelete: (_) {},
          onReact: (_, _) {},
          onOpenLink: opened.add,
        ),
        size: size,
      );

      expect(tester.takeException(), isNull);
      // The address wrapped rather than ran off the side.
      final body = find.byKey(const ValueKey('message_body_l2'));
      expect(tester.getSize(body).width, lessThan(size.width));
      expect(tester.getSize(body).height, greaterThan(40));
      expect(ChatMessageBody.linksIn(long).single.end, long.length);
    });
  });

  // #2496: encryption lines and unverified lines offer a "(?)" that explains
  // them; other system lines don't.
  testBothViewports('encryption and unverified lines offer help', (
    tester,
    size,
  ) async {
    final asked = <String>[];
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [
          msg('u', day2, kind: ChatMessageKind.system, isUnverified: true),
          ChatMessageItem(
            id: 'k',
            authorId: 'ada',
            authorName: 'Ada',
            sentAt: day1.add(const Duration(minutes: 1)),
            body: 'Ada set up encryption for this channel',
            kind: ChatMessageKind.system,
            isEncryptionEvent: true,
          ),
          msg('j', day1, kind: ChatMessageKind.system, body: 'Bob joined'),
        ],
        onEncryptionHelp: () => asked.add('help'),
      ),
      size: size,
    );

    expect(find.byKey(const ValueKey('message_help_j')), findsNothing);
    final help = find.byKey(const ValueKey('message_help_k'));
    expect(
      tester.widget<IconButton>(help).tooltip,
      QuarkMessageList.encryptionHelpTooltip,
    );
    await tester.tap(help);
    await tester.tap(find.byKey(const ValueKey('message_help_u')));
    expect(asked, ['help', 'help']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without onEncryptionHelp no line offers help', (tester) async {
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [
          msg('u', day2, kind: ChatMessageKind.system, isUnverified: true),
        ],
      ),
    );

    expect(find.byKey(const ValueKey('message_help_u')), findsNothing);
  });

  // #2424: the caller marks a channel read only while its newest message is
  // in view, so the list says when it is.
  testBothViewports('reports a short list as at the bottom after layout', (
    tester,
    size,
  ) async {
    final reports = <bool>[];
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [msg('m1', day1)],
        onAtBottomChanged: reports.add,
      ),
      size: size,
    );

    // No scroll happened: this is the first layout's metrics alone.
    expect(reports, isNotEmpty);
    expect(reports, everyElement(isTrue));
  });

  testBothViewports('reports leaving the bottom and coming back', (
    tester,
    size,
  ) async {
    final reports = <bool>[];
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [
          for (var i = 200; i > 0; i--)
            msg('m$i', day1.add(Duration(minutes: i)), body: 'message $i'),
        ],
        controller: controller,
        onAtBottomChanged: reports.add,
      ),
      size: size,
    );
    expect(reports.last, isTrue);

    controller.jumpTo(600);
    await tester.pump();
    expect(reports.last, isFalse);

    controller.jumpTo(0);
    await tester.pump();
    expect(reports.last, isTrue);
  });

  testBothViewports('reports the bottom when a message arrives', (
    tester,
    size,
  ) async {
    final reports = <bool>[];
    Widget list(int count) => QuarkMessageList(
      messages: [
        for (var i = count; i > 0; i--)
          msg('m$i', day1.add(Duration(minutes: i)), body: 'message $i'),
      ],
      onAtBottomChanged: reports.add,
    );
    await pumpAt(tester, list(200), size: size);
    reports.clear();

    // A new message with no scroll: only the content size changed.
    await pumpAt(tester, list(201), size: size);
    expect(reports, isNotEmpty);
    expect(reports.last, isTrue);
  });

  testWidgets('reports nothing where there is no list', (tester) async {
    final reports = <bool>[];
    for (final list in [
      QuarkMessageList(messages: const [], onAtBottomChanged: reports.add),
      QuarkMessageList(
        messages: const [],
        isLoading: true,
        onAtBottomChanged: reports.add,
      ),
      QuarkMessageList(
        messages: const [],
        error: "Couldn't load messages.",
        onAtBottomChanged: reports.add,
      ),
      QuarkMessageList(
        messages: messages,
        permissions: const {ChatPermission.manageMembers},
        onAtBottomChanged: reports.add,
      ),
    ]) {
      await pumpAt(tester, list);
    }

    expect(reports, isEmpty);
  });

  // #3255: scrolled up, a new message is counted on a pill. Tapping it
  // returns to the newest message and clears the count.
  testBothViewports(
    'shows the new-message count while scrolled up and clears it on tap',
    (tester, size) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final history = [
        for (var i = 40; i >= 1; i--)
          msg('m$i', day1.add(Duration(minutes: i)), body: 'message $i'),
      ];
      await pumpAt(
        tester,
        QuarkMessageList(messages: history, controller: controller),
        size: size,
      );
      expect(find.byKey(const ValueKey('message_list_jump')), findsNothing);

      expect(controller.position.maxScrollExtent, greaterThan(0));
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(find.text('1 new message'), findsNothing);

      await pumpAt(
        tester,
        QuarkMessageList(
          messages: [
            msg(
              'm41',
              day1.add(const Duration(minutes: 41)),
              body: 'just arrived',
            ),
            ...history,
          ],
          controller: controller,
        ),
        size: size,
      );

      expect(find.text('1 new message'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('message_list_jump')));
      await tester.pump();

      expect(
        controller.offset,
        lessThanOrEqualTo(QuarkMessageList.atBottomTolerance),
      );
      expect(find.byKey(const ValueKey('message_list_jump')), findsNothing);
      expect(find.text('just arrived'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // #2623: a mention of a member is drawn apart, and a message that mentions
  // the reader is highlighted.
  group('mentions', () {
    final mentioning = [
      msg('m3', day2.add(const Duration(minutes: 2)), body: 'plain words'),
      msg('m2', day2.add(const Duration(minutes: 1)), body: 'ask @Bob or @zed'),
      msg('m1', day2, author: 'bob', body: 'hey @ada, see https://a.example'),
    ];

    List<String> mentionsIn(WidgetTester tester, String id) {
      final spans = <String>[];
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(ValueKey('message_body_$id')),
              matching: find.byType(Text),
            ),
          )
          .textSpan
          ?.visitChildren((span) {
            if (span is TextSpan && span.style?.backgroundColor != null) {
              spans.add(span.text!);
            }
            return true;
          });
      return spans;
    }

    testBothViewports('draws members mentioned and highlights the reader', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: mentioning,
          mentionNames: const ['ada', 'bob'],
          currentUserName: 'ada',
          onOpenLink: (_) {},
        ),
        size: size,
      );

      expect(mentionsIn(tester, 'm1'), ['@ada']);
      expect(mentionsIn(tester, 'm2'), ['@Bob']);
      expect(mentionsIn(tester, 'm3'), isEmpty);
      expect(find.textRange.ofSubstring('https://a.example'), findsOneWidget);
      expect(find.byKey(const ValueKey('message_mention_m1')), findsOneWidget);
      expect(find.byKey(const ValueKey('message_mention_m2')), findsNothing);
      expect(find.byKey(const ValueKey('message_mention_m3')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Mentions you')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without names or a reader nothing is marked', (tester) async {
      await pumpAt(tester, QuarkMessageList(messages: mentioning));
      expect(mentionsIn(tester, 'm1'), isEmpty);
      expect(find.byKey(const ValueKey('message_mention_m1')), findsNothing);

      await pumpAt(
        tester,
        QuarkMessageList(
          messages: mentioning,
          mentionNames: const ['ada', 'bob'],
        ),
      );
      expect(mentionsIn(tester, 'm1'), ['@ada']);
      expect(find.byKey(const ValueKey('message_mention_m1')), findsNothing);
    });

    testBothViewports('an unverified message draws no mention', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: [msg('m1', day2, body: 'hey @ada', isUnverified: true)],
          mentionNames: const ['ada'],
          currentUserName: 'ada',
        ),
        size: size,
      );

      expect(mentionsIn(tester, 'm1'), isEmpty);
      expect(find.byKey(const ValueKey('message_mention_m1')), findsNothing);
    });
  });

  // #3257: opened from the keyboard, the reaction menu left focus on its
  // button, so the arrow keys walked on to the next message's button and
  // Enter opened that row's menu instead. And the first reaction grew the row
  // upward, moving the button just used out from under the focus.
  group('reacting from the keyboard (#3257)', () {
    List<ChatMessageItem> thread(Set<String> reacted) => [
      for (var i = 6; i >= 1; i--)
        ChatMessageItem(
          id: 'k$i',
          authorId: i.isEven ? 'ada' : 'bob',
          authorName: i.isEven ? 'Ada' : 'Bob',
          sentAt: day2.add(Duration(minutes: i)),
          body: 'line $i',
          reactions: [
            if (reacted.contains('k$i'))
              const ChatReactionItem(emoji: '❤️', count: 1, reactedByMe: true),
          ],
        ),
    ];

    /// Tabs until focus is on [target]'s add-reaction button.
    Future<void> tabTo(WidgetTester tester, String target) async {
      for (var i = 0; i < 60; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused?.findAncestorWidgetOfExactType<IconButton>()?.key ==
            ValueKey(target)) {
          return;
        }
      }
      fail('Tab never reached $target');
    }

    String? focusedMenuItem() => switch (FocusManager
        .instance
        .primaryFocus
        ?.context
        ?.findAncestorWidgetOfExactType<MenuItemButton>()
        ?.key) {
      ValueKey<String>(:final value) => value,
      _ => null,
    };

    testBothViewports(
      'the menu is the focused row\'s, and the row holds still',
      (tester, size) async {
        final reacted = <String>{};
        final events = <String>[];
        await pumpAt(
          tester,
          StatefulBuilder(
            builder: (context, setState) => QuarkMessageList(
              messages: thread(reacted),
              onReact: (id, emoji) => setState(() {
                events.add('$id $emoji');
                reacted.add(id);
              }),
            ),
          ),
          size: size,
        );
        final button = find.byKey(const ValueKey('message_react_k3'));
        final before = tester.getRect(button);

        await tabTo(tester, 'message_react_k3');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(focusedMenuItem(), 'message_react_k3_👍');
        // The menu stands against the button it came from.
        final first = tester.getRect(
          find.byKey(const ValueKey('message_react_k3_👍')),
        );
        final last = tester.getRect(
          find.byKey(
            ValueKey('message_react_k3_${ChatReactionPicker.choices.last}'),
          ),
        );
        final menu = first.expandToInclude(last);
        expect(
          menu.top >= before.top - 1 || menu.bottom <= before.bottom + 1,
          isTrue,
          reason: 'menu $menu is away from its button $before',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(focusedMenuItem(), 'message_react_k3_❤️');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(events, ['k3 ❤️']);
        expect(
          find.byKey(const ValueKey('message_reaction_k3_❤️')),
          findsOneWidget,
        );
        expect(tester.getRect(button), before);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<IconButton>()
              ?.key,
          const ValueKey('message_react_k3'),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a pointer opens the menu without focusing into it', (
      tester,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageList(messages: thread(const {}), onReact: (_, _) {}),
      );

      await tester.tap(find.byKey(const ValueKey('message_react_k3')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('message_react_k3_👍')), findsOneWidget);
      expect(focusedMenuItem(), isNull);
    });
  });

  // #3257: text ran the whole width of a desktop window.
  testBothViewports('wraps long text at a readable width', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: [msg('long', day1, body: 'word ' * 200)],
        onReact: (_, _) {},
      ),
      size: size,
    );

    final body = tester.getRect(
      find.byKey(const ValueKey('message_body_long')),
    );
    expect(body.width, lessThanOrEqualTo(ChatMessageRow.maxBodyWidth));
    // The buttons stay at the row's end, not after the text.
    expect(
      tester.getRect(find.byKey(const ValueKey('message_react_long'))).right,
      greaterThan(size.width - 120),
    );
    expect(tester.takeException(), isNull);
  });
}

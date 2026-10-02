import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark_widgets/src/chat/quark_message_list/chat_message_row/chat_message_body.dart';

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

  testBothViewports('shows a spinner while the first page loads', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkMessageList(messages: [], isLoading: true),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
  });

  testBothViewports('renders the error the caller handed it', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkMessageList(messages: [], error: "Couldn't load messages."),
      size: size,
    );

    expect(find.text("Couldn't load messages."), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.text('No messages yet'), findsNothing);
  });

  testBothViewports('retries the first page after it fails', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: const [],
        error: "Couldn't load messages.",
        onLoadOlder: () => events.add('load'),
      ),
      size: size,
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

  testBothViewports('says so when the channel is empty', (tester, size) async {
    await pumpAt(tester, const QuarkMessageList(messages: []), size: size);

    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('renders every message with its key', (tester, size) async {
    await pumpAt(tester, QuarkMessageList(messages: messages), size: size);

    for (final message in messages) {
      expect(find.byKey(ValueKey('message_${message.id}')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
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

  testBothViewports('groups one author under one header and splits days', (
    tester,
    size,
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
      size: size,
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

  testBothViewports('asks for older messages from the load button', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: messages,
        hasMore: true,
        onLoadOlder: () => events.add('older'),
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('message_list_load_older')));
    await tester.pump();

    expect(events, ['older']);
  });

  testBothViewports('shows progress at the top while older ones load', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMessageList(messages: messages, hasMore: true, isLoading: true),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byKey(const ValueKey('message_list_load_older')), findsNothing);
    expect(find.byKey(const ValueKey('message_m1')), findsOneWidget);
  });

  testBothViewports('retries older messages after an error', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkMessageList(
        messages: messages,
        hasMore: true,
        error: "Couldn't load older messages.",
        onLoadOlder: () => events.add('older'),
      ),
      size: size,
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

    testBothViewports('the menu button opens it from the keyboard', (
      tester,
      size,
    ) async {
      final copied = <String>[];
      await pumpAt(
        tester,
        QuarkMessageList(messages: messages, onCopy: copied.add),
        size: size,
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

    testBothViewports('a viewer without add_reactions gets no Add reaction', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: messages,
          permissions: ChatPermissionPreset.viewer.permissions,
          onCopy: (_) {},
          onReact: (_, _) {},
        ),
        size: size,
      );

      await tester.tap(key('message_menu_m4'));
      await tester.pumpAndSettle();
      expect(find.text('Copy text'), findsOneWidget);
      expect(find.text('Add reaction'), findsNothing);
    });

    testBothViewports('a moderator may delete any text message', (
      tester,
      size,
    ) async {
      final deleted = <String>[];
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: messages,
          permissions: ChatPermissionPreset.moderator.permissions,
          currentUserId: 'ada',
          onDelete: deleted.add,
        ),
        size: size,
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

    testBothViewports('without delete_messages only the author may delete', (
      tester,
      size,
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
        size: size,
      );

      expect(await offersDelete(tester, 'm2'), isTrue);
      expect(await offersDelete(tester, 'm4'), isFalse);
    });

    testBothViewports('a viewer sees no delete on anyone else\'s message', (
      tester,
      size,
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
        size: size,
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

      for (final size in [narrowViewport, wideViewport]) {
        testWidgets('dragging the mouse selects message text ($size)', (
          tester,
        ) async {
          await pumpAt(
            tester,
            QuarkMessageList(messages: linked, onCopy: (_) {}),
            size: size,
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

        testWidgets('a right-click opens the menu, not a toolbar ($size)', (
          tester,
        ) async {
          final copied = <String>[];
          await pumpAt(
            tester,
            QuarkMessageList(messages: linked, onCopy: copied.add),
            size: size,
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

        testWidgets('a long press is not the menu\'s ($size)', (tester) async {
          await pumpAt(
            tester,
            QuarkMessageList(messages: linked, onCopy: (_) {}),
            size: size,
          );

          await tester.longPress(key('message_body_m1'));
          await tester.pumpAndSettle();

          expect(find.byType(PopupMenuItem<int>), findsNothing);
          expect(key('message_menu_m1'), findsOneWidget);
        }, variant: desktop);

        testWidgets('a link still opens inside the selection area ($size)', (
          tester,
        ) async {
          final opened = <Uri>[];
          await pumpAt(
            tester,
            QuarkMessageList(messages: linked, onOpenLink: opened.add),
            size: size,
          );
          expect(find.byType(SelectionArea), findsOneWidget);

          await tester.tapOnText(find.textRange.ofSubstring('https://a.com/x'));
          await tester.pump();

          expect(opened, [Uri.parse('https://a.com/x')]);
        }, variant: desktop);
      }
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

    testBothViewports('a viewer without add_reactions only sees them', (
      tester,
      size,
    ) async {
      final events = <String>[];
      await pumpAt(
        tester,
        QuarkMessageList(
          messages: reacted,
          permissions: ChatPermissionPreset.viewer.permissions,
          onReact: (id, emoji) => events.add('$id $emoji'),
        ),
        size: size,
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
}

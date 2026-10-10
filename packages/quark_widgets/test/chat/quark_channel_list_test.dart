import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The chat server's channel list (#2420): every state on its own, the open
/// channel highlighted, private channels locked, and taps reported by id.
void main() {
  const channels = [
    ChatChannelItem(id: 'general', name: 'general'),
    ChatChannelItem(id: 'family', name: 'family', isPrivate: true),
    ChatChannelItem(id: 'books', name: 'books'),
  ];

  testBothViewports('shows a spinner while loading and no channels', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkChannelList(
        serverName: 'Home',
        channels: channels,
        isLoading: true,
      ),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byKey(const ValueKey('channel_tile_general')), findsNothing);
    expect(find.text('No channels yet'), findsNothing);
  });

  testBothViewports('renders the error the caller handed it', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkChannelList(
        serverName: 'Home',
        channels: channels,
        error: "Couldn't load the channels.",
      ),
      size: size,
    );

    expect(find.text("Couldn't load the channels."), findsOneWidget);
    expect(find.byKey(const ValueKey('channel_tile_general')), findsNothing);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('shows the empty copy when there are no channels', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkChannelList(serverName: 'Home', channels: []),
      size: size,
    );

    expect(find.text('No channels yet'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('renders every channel under the server name', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkChannelList(serverName: 'Home', channels: channels),
      size: size,
    );

    expect(find.byKey(const ValueKey('channel_list_header')), findsOneWidget);
    for (final channel in channels) {
      expect(
        find.byKey(ValueKey('channel_tile_${channel.id}')),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testBothViewports('locks only the private channels', (tester, size) async {
    await pumpAt(
      tester,
      const QuarkChannelList(serverName: 'Home', channels: channels),
      size: size,
    );

    expect(find.byIcon(QuarkIcons.lock_outline), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('channel_tile_family')),
        matching: find.byIcon(QuarkIcons.lock_outline),
      ),
      findsOneWidget,
    );
  });

  testBothViewports('highlights the open channel', (tester, size) async {
    await pumpAt(
      tester,
      const QuarkChannelList(
        serverName: 'Home',
        channels: channels,
        selectedChannelId: 'books',
      ),
      size: size,
    );

    bool selected(String id) => tester
        .widget<ListTile>(find.byKey(ValueKey('channel_tile_$id')))
        .selected;
    expect(selected('books'), isTrue);
    expect(selected('general'), isFalse);
    expect(selected('family'), isFalse);
  });

  testBothViewports('reports the channel that was tapped', (
    tester,
    size,
  ) async {
    final selected = <String>[];
    await pumpAt(
      tester,
      QuarkChannelList(
        serverName: 'Home',
        channels: channels,
        onSelect: selected.add,
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('channel_tile_family')));
    await tester.tap(find.byKey(const ValueKey('channel_tile_general')));
    await tester.pump();

    expect(selected, ['family', 'general']);
  });

  testBothViewports('survives long names and many channels', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkChannelList(
        serverName: 'The Lovelace family server ' * 10,
        channels: [
          for (var i = 0; i < 200; i++)
            ChatChannelItem(
              id: '$i',
              name: 'a${'n' * 200}',
              isPrivate: i.isEven,
            ),
        ],
        selectedChannelId: '0',
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('lists other channels under their own heading', (
    tester,
    size,
  ) async {
    final selected = <String>[];
    await pumpAt(
      tester,
      QuarkChannelList(
        serverName: 'Home',
        channels: channels,
        otherChannels: const [
          ChatChannelItem(id: 'secret', name: 'secret', isPrivate: true),
        ],
        selectedChannelId: 'secret',
        onSelect: selected.add,
      ),
      size: size,
    );

    expect(
      find.byKey(const ValueKey('channel_list_other_header')),
      findsOneWidget,
    );
    expect(find.text('Other channels'), findsOneWidget);
    final tile = find.byKey(const ValueKey('channel_tile_secret'));
    expect(tester.widget<ListTile>(tile).selected, isTrue);
    await tester.tap(tile);
    expect(selected, ['secret']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows no other heading without other channels', (tester) async {
    await pumpAt(
      tester,
      const QuarkChannelList(serverName: 'Home', channels: channels),
    );

    expect(
      find.byKey(const ValueKey('channel_list_other_header')),
      findsNothing,
    );
  });

  testBothViewports('names what the account may do in each channel', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkChannelList(
        serverName: 'Home',
        channels: [
          ChatChannelItem(
            id: '1',
            name: 'general',
            permissions: {
              ChatPermission.readMessages,
              ChatPermission.sendMessages,
              ChatPermission.addReactions,
            },
          ),
          ChatChannelItem(
            id: '2',
            name: 'ops',
            permissions: {ChatPermission.manageMembers},
          ),
          ChatChannelItem(id: '3', name: 'plain'),
        ],
      ),
      size: size,
    );

    expect(find.text('Member'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // #2424: a channel with messages the account has not read says so.
  testBothViewports('shows an unread channel in bold with its count', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const QuarkChannelList(
        serverName: 'Home',
        channels: [
          ChatChannelItem(id: 'general', name: 'general', unreadCount: 3),
          ChatChannelItem(id: 'one', name: 'one', unreadCount: 1),
          ChatChannelItem(id: 'books', name: 'books'),
        ],
      ),
      size: size,
    );

    final pill = find.byKey(const ValueKey('channel_unread_general'));
    expect(find.descendant(of: pill, matching: find.text('3')), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('general')).style?.fontWeight,
      FontWeight.w700,
    );
    expect(find.byTooltip('3 unread messages'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('3 unread messages')), findsOneWidget);
    expect(find.byTooltip('1 unread message'), findsOneWidget);

    // Read: no pill, and the name exactly as it was drawn before.
    expect(find.byKey(const ValueKey('channel_unread_books')), findsNothing);
    expect(tester.widget<Text>(find.text('books')).style, isNull);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('caps the unread count at 99+', (tester, size) async {
    await pumpAt(
      tester,
      const QuarkChannelList(
        serverName: 'Home',
        channels: [
          ChatChannelItem(id: 'a', name: 'a', unreadCount: 99),
          ChatChannelItem(id: 'b', name: 'b', unreadCount: 100),
        ],
      ),
      size: size,
    );

    expect(find.text('99'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
    expect(find.byTooltip('100 unread messages'), findsOneWidget);
  });

  testBothViewports('fits a long name with an unread count and a lock', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkChannelList(
        serverName: 'Home',
        channels: [
          ChatChannelItem(
            id: 'long',
            name: 'a${'n' * 200}',
            isPrivate: true,
            unreadCount: 1234,
          ),
        ],
      ),
      size: size,
    );

    final tile = find.byKey(const ValueKey('channel_tile_long'));
    final pill = find.byKey(const ValueKey('channel_unread_long'));
    final lock = find.descendant(
      of: tile,
      matching: find.byIcon(QuarkIcons.lock_outline),
    );
    expect(find.text('99+'), findsOneWidget);
    expect(lock, findsOneWidget);
    // Both sit inside the row, the pill before the lock.
    expect(
      tester.getRect(pill).right,
      lessThanOrEqualTo(tester.getRect(lock).left),
    );
    expect(
      tester.getRect(lock).right,
      lessThanOrEqualTo(tester.getRect(tile).right),
    );
    expectNoClippedText(tester);
    expect(tester.takeException(), isNull);
  });
}

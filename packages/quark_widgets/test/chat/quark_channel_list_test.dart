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
}

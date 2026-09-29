import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The chat page's frame (#2420): three panes on a wide window, messages
/// alone on a narrow one, with the channels in a drawer and the members in a
/// sheet that the caller opens and closes.
void main() {
  const channels = ValueKey('channels_body');
  const messages = ValueKey('messages_body');
  const members = ValueKey('members_body');

  QuarkChatLayout layout({
    bool channelsOpen = false,
    bool membersOpen = false,
    bool withMembers = true,
    List<String>? events,
  }) => QuarkChatLayout(
    header: const Text('# general'),
    channelList: const SizedBox.expand(key: channels),
    messages: const SizedBox.expand(key: messages),
    memberList: withMembers ? const SizedBox.expand(key: members) : null,
    isChannelListOpen: channelsOpen,
    isMemberListOpen: membersOpen,
    onToggleChannelList: events == null ? null : () => events.add('channels'),
    onToggleMemberList: events == null ? null : () => events.add('members'),
  );

  testWidgets('wide: shows all three panes side by side', (tester) async {
    await pumpAt(tester, layout(), size: wideViewport);

    expect(find.byKey(channels), findsOneWidget);
    expect(find.byKey(messages), findsOneWidget);
    expect(find.byKey(members), findsOneWidget);
    expect(find.text('# general'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('chat_layout_channels'))).width,
      QuarkChatLayout.channelListWidth,
    );
    expect(
      tester.getTopLeft(find.byKey(channels)).dx,
      lessThan(tester.getTopLeft(find.byKey(messages)).dx),
    );
    expect(
      tester.getTopLeft(find.byKey(messages)).dx,
      lessThan(tester.getTopLeft(find.byKey(members)).dx),
    );
    expect(
      find.byKey(const ValueKey('chat_layout_channels_toggle')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide: leaves the member pane out without a member list', (
    tester,
  ) async {
    await pumpAt(tester, layout(withMembers: false), size: wideViewport);

    expect(find.byKey(const ValueKey('chat_layout_members')), findsNothing);
    expect(find.byKey(messages), findsOneWidget);
  });

  testWidgets('narrow: shows messages alone with both buttons', (tester) async {
    await pumpAt(tester, layout(), size: narrowViewport);

    expect(find.byKey(messages), findsOneWidget);
    expect(find.byKey(channels), findsNothing);
    expect(find.byKey(members), findsNothing);
    expect(find.text('# general'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat_layout_channels_toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat_layout_members_toggle')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow: the buttons report which pane to toggle', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(tester, layout(events: events), size: narrowViewport);

    await tester.tap(find.byKey(const ValueKey('chat_layout_channels_toggle')));
    await tester.tap(find.byKey(const ValueKey('chat_layout_members_toggle')));
    await tester.pump();

    expect(events, ['channels', 'members']);
  });

  testWidgets('narrow: an open drawer shows the channels over a scrim', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      layout(channelsOpen: true, events: events),
      size: narrowViewport,
    );

    expect(find.byKey(channels), findsOneWidget);
    expect(find.byKey(members), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('chat_layout_channels'))).width,
      QuarkChatLayout.channelListWidth,
    );

    await tester.tapAt(const Offset(350, 320));
    await tester.pump();
    expect(events, ['channels']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow: an open sheet shows the members over a scrim', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      layout(membersOpen: true, events: events),
      size: narrowViewport,
    );

    expect(find.byKey(members), findsOneWidget);
    expect(find.byKey(channels), findsNothing);
    expect(
      tester
          .getBottomLeft(find.byKey(const ValueKey('chat_layout_members')))
          .dy,
      narrowViewport.height,
    );

    await tester.tapAt(const Offset(180, 60));
    await tester.pump();
    expect(events, ['members']);
  });

  testWidgets('narrow: no member button without a member list', (tester) async {
    await pumpAt(
      tester,
      layout(withMembers: false, membersOpen: true),
      size: narrowViewport,
    );

    expect(
      find.byKey(const ValueKey('chat_layout_members_toggle')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('chat_layout_scrim')), findsNothing);
  });

  testWidgets('every icon-only button carries a tooltip', (tester) async {
    await pumpAt(tester, layout(), size: narrowViewport);
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.tooltip, isNotNull);
    }
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: panes take the sidebar token', (tester) async {
      await pumpAt(tester, layout(), brightness: brightness);

      final pane = tester.widget<Material>(
        find.byKey(const ValueKey('chat_layout_channels')),
      );
      expect(pane.color, tokens.sidebar);
    });
  }
}

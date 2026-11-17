import 'package:material_ui/material_ui.dart';
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

  /// A wide layout whose pane widths and collapsed flags live in a
  /// StatefulBuilder, the way the chat page holds them, with every change
  /// recorded in [events].
  Widget resizable(List<String> events, {bool channelsCollapsed = false}) {
    var channelWidth = QuarkChatLayout.channelListWidth;
    var memberWidth = QuarkChatLayout.memberListWidth;
    var channelsGone = channelsCollapsed;
    var membersGone = false;
    return StatefulBuilder(
      builder: (context, setState) => QuarkChatLayout(
        header: const Text('# general'),
        channelList: const SizedBox.expand(key: channels),
        messages: const SizedBox.expand(key: messages),
        memberList: const SizedBox.expand(key: members),
        channelPaneWidth: channelWidth,
        isChannelPaneCollapsed: channelsGone,
        onChannelPaneWidthChanged: (w) => setState(() {
          events.add('channels width ${w.round()}');
          channelWidth = w;
        }),
        onChannelPaneCollapsedChanged: (c) => setState(() {
          events.add('channels collapsed $c');
          channelsGone = c;
        }),
        memberPaneWidth: memberWidth,
        isMemberPaneCollapsed: membersGone,
        onMemberPaneWidthChanged: (w) => setState(() {
          events.add('members width ${w.round()}');
          memberWidth = w;
        }),
        onMemberPaneCollapsedChanged: (c) => setState(() {
          events.add('members collapsed $c');
          membersGone = c;
        }),
      ),
    );
  }

  testWidgets('wide: dragging a handle resizes its pane (#4294)', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(tester, resizable(events), size: wideViewport);

    await tester.drag(
      find.byKey(const ValueKey('resizable_pane_handle_chat_channels')),
      const Offset(20, 0),
    );
    await tester.drag(
      find.byKey(const ValueKey('resizable_pane_handle_chat_members')),
      const Offset(-20, 0),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('chat_layout_channels'))).width,
      QuarkChatLayout.channelListWidth + 20,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('chat_layout_members'))).width,
      QuarkChatLayout.memberListWidth + 20,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide: both panes together leave the messages half the window', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(tester, resizable(events), size: wideViewport);

    await tester.drag(
      find.byKey(const ValueKey('resizable_pane_handle_chat_channels')),
      const Offset(400, 0),
    );
    await tester.drag(
      find.byKey(const ValueKey('resizable_pane_handle_chat_members')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(messages)).width,
      greaterThanOrEqualTo(
        wideViewport.width / 2 - 2 * QuarkResizablePane.handleWidth,
      ),
    );
  });

  testWidgets('wide: the header buttons collapse and reopen the panes', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(tester, resizable(events), size: wideViewport);

    expect(find.byTooltip('Hide channels'), findsOneWidget);
    expect(find.byTooltip('Hide members'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat_layout_channels_toggle')));
    await tester.tap(find.byKey(const ValueKey('chat_layout_members_toggle')));
    await tester.pumpAndSettle();

    expect(events, ['channels collapsed true', 'members collapsed true']);
    expect(find.byKey(channels), findsNothing);
    expect(find.byKey(members), findsNothing);
    expect(find.byTooltip('Show channels'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat_layout_channels_toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(channels), findsOneWidget);
  });

  testWidgets('wide: a collapsed channel list leaves no rail', (tester) async {
    await pumpAt(
      tester,
      resizable([], channelsCollapsed: true),
      size: wideViewport,
    );

    expect(find.byKey(channels), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(messages)).dx,
      QuarkResizablePane.handleWidth,
    );
  });

  testWidgets('narrow: resizable panes keep the drawer and sheet', (
    tester,
  ) async {
    await pumpAt(tester, resizable([]), size: narrowViewport);

    expect(find.byType(QuarkResizablePane), findsNothing);
    expect(find.byTooltip('Channels'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('narrow: the member sheet closes from its close button', (
    tester,
  ) async {
    final events = <String>[];
    await pumpAt(
      tester,
      layout(membersOpen: true, events: events),
      size: narrowViewport,
    );

    await tester.tap(find.byKey(const ValueKey('quark_sheet_close')));
    await tester.pump();
    expect(events, ['members']);
    expect(tester.takeException(), isNull);
  });

  // #2585: back used to pop the whole chat page with the sheet still open.
  // With nothing open, back leaves the page as usual.
  for (final (name, open, events, page) in [
    (
      'narrow: back closes an open sheet, not the page',
      (List<String> e) => layout(membersOpen: true, events: e),
      ['members'],
      findsOneWidget,
    ),
    (
      'narrow: back closes an open drawer, not the page',
      (List<String> e) => layout(channelsOpen: true, events: e),
      ['channels'],
      findsOneWidget,
    ),
    (
      'narrow: back leaves the page when nothing is open',
      (List<String> e) => layout(events: e),
      <String>[],
      findsNothing,
    ),
  ]) {
    testWidgets(name, (tester) async {
      final seen = <String>[];
      await pumpAt(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(body: open(seen)),
              ),
            ),
            child: const Text('open chat'),
          ),
        ),
        size: narrowViewport,
      );
      await tester.tap(find.text('open chat'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(seen, events);
      expect(find.byType(QuarkChatLayout), page);
    });
  }

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

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(tester, layout(events: []), size: size);

    for (final key in const [
      'chat_layout_channels_toggle',
      'chat_layout_members_toggle',
    ]) {
      if (find.byKey(ValueKey(key)).evaluate().isEmpty) continue;
      expect(
        tester.getSize(find.byKey(ValueKey(key))),
        const Size.square(QuarkBarIconButton.tapTargetSize),
        reason: key,
      );
    }
    await expectTapTargetGuidelines(tester);
  });
}

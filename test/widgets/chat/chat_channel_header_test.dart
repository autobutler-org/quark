import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/chat/chat_channel_header.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The channel header's settings menu keeps leave and delete apart from the
/// routine actions (#2498), and a private channel says what its lock means
/// (#2501), on narrow and wide viewports alike.
void main() {
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pumpHeader(
    WidgetTester tester,
    Size size,
    ChatChannelHeader header,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(body: header),
      ),
    );
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(key('chat_channel_settings'));
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String k) => tester.getTopLeft(key(k)).dy;

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('a divider puts leave and delete after the rest at $size', (
      tester,
    ) async {
      final log = <String>[];
      await pumpHeader(
        tester,
        size,
        ChatChannelHeader(
          name: 'design',
          onEdit: () => log.add('edit'),
          onMembers: () => log.add('members'),
          onLeave: () => log.add('leave'),
          onDelete: () => log.add('delete'),
        ),
      );
      await openMenu(tester);

      final divider = top(tester, 'chat_channel_menu_divider');
      expect(top(tester, 'chat_channel_members'), lessThan(divider));
      expect(top(tester, 'chat_channel_leave'), greaterThan(divider));
      expect(
        top(tester, 'chat_channel_delete'),
        greaterThan(top(tester, 'chat_channel_leave')),
      );
      expect(find.text('Delete channel for everyone'), findsOneWidget);
      expect(find.text('Leave channel'), findsOneWidget);

      await tester.tap(key('chat_channel_delete'));
      await tester.pumpAndSettle();
      expect(log, ['delete']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no divider without both kinds at $size', (tester) async {
      await pumpHeader(
        tester,
        size,
        ChatChannelHeader(name: 'general', onEdit: () {}, onMembers: () {}),
      );
      await openMenu(tester);
      expect(key('chat_channel_menu_divider'), findsNothing);

      await pumpHeader(
        tester,
        size,
        ChatChannelHeader(name: 'design', onLeave: () {}),
      );
      await tester.pumpAndSettle();
      await openMenu(tester);
      expect(key('chat_channel_menu_divider'), findsNothing);
    });

    testWidgets('a private channel explains its lock at $size', (tester) async {
      await pumpHeader(
        tester,
        size,
        const ChatChannelHeader(name: 'design', isPrivate: true),
      );
      expect(key('chat_channel_private'), findsOneWidget);
      expect(find.byTooltip(ChatChannelHeader.privateTooltip), findsOneWidget);

      await pumpHeader(tester, size, const ChatChannelHeader(name: 'general'));
      expect(key('chat_channel_private'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

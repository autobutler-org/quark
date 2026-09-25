import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/pages/chat_page.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/fake_chat.dart';

/// The chat page (#2421) composes the chat widgets over a [FakeChat], at a
/// phone's size and a desktop's.
void main() {
  const narrow = Size(360, 640);
  const wide = Size(1280, 800);

  Future<(GoRouter, FakeChat)> pumpChat(
    WidgetTester tester,
    Size size, {
    String location = '/chat/general',
    FakeChat? chat,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = chat ?? FakeChat();
    final r = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '${AppRoutes.chat}/:channelId',
          builder: (context, state) => ChatPage(
            channelId: state.pathParameters['channelId']!,
            controller: fake.controller,
          ),
        ),
      ],
    );
    addTearDown(r.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();
    return (r, fake);
  }

  String at(GoRouter r) => r.routerDelegate.currentConfiguration.uri.toString();

  for (final (label, size) in [('narrow', narrow), ('wide', wide)]) {
    testWidgets('opens general and moves the URL to its id ($label)', (
      tester,
    ) async {
      final (r, _) = await pumpChat(tester, size);

      expect(at(r), '/chat/1');
      expect(find.text('# general'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('message_composer_field')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a sent message shows at once ($label)', (tester) async {
      final (_, fake) = await pumpChat(tester, size);

      await tester.enterText(
        find.byKey(const ValueKey('message_composer_field')),
        'hello',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('message_composer_send')));
      await tester.pumpAndSettle();

      expect(fake.opened[1]!.sent, ['hello']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed send offers retry ($label)', (tester) async {
      final (_, fake) = await pumpChat(tester, size);
      fake.opened[1]!.onSend = (_) async =>
          throw const MessageException('offline');

      await tester.enterText(
        find.byKey(const ValueKey('message_composer_field')),
        'hello',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('message_composer_send')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat_failed_send_retry')),
        findsOneWidget,
      );

      fake.opened[1]!.onSend = null;
      await tester.tap(find.byKey(const ValueKey('chat_failed_send_retry')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat_failed_send_retry')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('locked chat asks for the password first ($label)', (
      tester,
    ) async {
      final (_, fake) = await pumpChat(
        tester,
        size,
        chat: FakeChat(unlocked: false),
      );

      expect(
        find.byKey(const ValueKey('chat_unlock_password')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('message_composer_field')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat_unlock_password')),
        'wrong',
      );
      await tester.tap(find.byKey(const ValueKey('chat_unlock_submit')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat_unlock_password')),
        findsOneWidget,
      );
      expect(
        find.textContaining("Couldn't unlock your messages"),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat_unlock_password')),
        'right',
      );
      await tester.tap(find.byKey(const ValueKey('chat_unlock_submit')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('message_composer_field')),
        findsOneWidget,
      );
      expect(fake.opened[1]!.opens, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('waiting for a key closes the composer ($label)', (
      tester,
    ) async {
      final fake = FakeChat()..waiting.add(1);
      await pumpChat(tester, size, chat: fake);

      expect(
        find.byKey(const ValueKey('message_composer_disabled')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  for (final (label, size) in [('narrow', narrow), ('wide', wide)]) {
    testWidgets('creates a channel and goes to it ($label)', (tester) async {
      final (r, fake) = await pumpChat(tester, size);

      await tapKey(tester, 'chat_new_channel');
      await tester.enterText(
        find.byKey(const ValueKey('channel_dialog_name')),
        'design',
      );
      await tester.enterText(
        find.byKey(const ValueKey('channel_dialog_topic')),
        'Mockups',
      );
      await tester.pump();
      await tapKey(tester, 'channel_dialog_submit');

      expect(fake.calls, ['create design "Mockups"', 'ensure keys 12']);
      expect(find.byType(QuarkChannelDialog), findsNothing);
      expect(at(r), '/chat/12');
      expect(find.text('# design'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a taken name keeps the dialog open ($label)', (tester) async {
      final (r, fake) = await pumpChat(tester, size);
      fake.failWith = const ApiException(409);

      await tapKey(tester, 'chat_new_channel');
      await tester.enterText(
        find.byKey(const ValueKey('channel_dialog_name')),
        'random',
      );
      await tester.pump();
      await tapKey(tester, 'channel_dialog_submit');

      expect(find.text(Errors.chatChannelNameTaken), findsOneWidget);
      expect(find.byType(QuarkChannelDialog), findsOneWidget);
      expect(at(r), '/chat/1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('an owner renames, then deletes, a channel ($label)', (
      tester,
    ) async {
      final (r, fake) = await pumpChat(tester, size, location: '/chat/2');

      await tapKey(tester, 'chat_channel_settings');
      await tapKey(tester, 'chat_channel_edit');
      await tester.enterText(
        find.byKey(const ValueKey('channel_dialog_name')),
        'ideas',
      );
      await tester.pump();
      await tapKey(tester, 'channel_dialog_submit');
      expect(find.text('# ideas'), findsOneWidget);

      await tapKey(tester, 'chat_channel_settings');
      await tapKey(tester, 'chat_channel_delete');
      await tester.enterText(
        find.byKey(const ValueKey('delete_channel_field')),
        'ideas',
      );
      await tester.pump();
      await tapKey(tester, 'delete_channel_confirm');

      expect(fake.calls, ['update 2 ideas ""', 'delete 2']);
      expect(at(r), '/chat/1');
      expect(find.text('# general'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a member leaves a channel ($label)', (tester) async {
      final (r, fake) = await pumpChat(tester, size, location: '/chat/2');

      await tapKey(tester, 'chat_channel_settings');
      await tapKey(tester, 'chat_channel_leave');
      expect(find.text('Leave #random?'), findsOneWidget);
      await tapKey(tester, 'leave_channel_confirm');

      expect(fake.calls, [
        'remove 2 user=7 group=null',
        'sign 42 user=7 level=null',
      ]);
      expect(at(r), '/chat/1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a refused leave says why ($label)', (tester) async {
      final (r, fake) = await pumpChat(tester, size, location: '/chat/2');
      fake.failWith = const MessageException(
        'this would leave the channel without an owner',
      );

      await tapKey(tester, 'chat_channel_settings');
      await tapKey(tester, 'chat_channel_leave');
      await tapKey(tester, 'leave_channel_confirm');

      expect(
        find.text('This would leave the channel without an owner.'),
        findsOneWidget,
      );
      expect(at(r), '/chat/2');
      expect(tester.takeException(), isNull);
    });

    testWidgets('general offers a writer no settings ($label)', (tester) async {
      await pumpChat(tester, size);

      expect(find.text('# general'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat_channel_settings')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an admin opens a channel they are not in without its messages', (
    tester,
  ) async {
    final (r, fake) = await pumpChat(
      tester,
      wide,
      location: '/chat/9',
      chat: FakeChat(
        isAdmin: true,
        otherChannels: const [
          ChatChannel(id: 9, name: 'payroll', isPrivate: true),
        ],
      ),
    );

    expect(at(r), '/chat/9');
    expect(find.text('Other channels'), findsOneWidget);
    expect(find.text('# payroll'), findsOneWidget);
    expect(fake.opened[9], isNull);
    expect(
      find.byKey(const ValueKey('message_composer_disabled')),
      findsOneWidget,
    );

    await tapKey(tester, 'chat_channel_settings');
    expect(find.byKey(const ValueKey('chat_channel_members')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_channel_delete')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_channel_leave')), findsNothing);
  });

  testWidgets('picking a channel goes to its URL and closes the drawer', (
    tester,
  ) async {
    final (r, fake) = await pumpChat(tester, narrow);

    await tester.tap(find.byKey(const ValueKey('chat_layout_channels_toggle')));
    await tester.pumpAndSettle();
    expect(fake.controller.isChannelListOpen, isTrue);
    await tester.tap(find.text('random'));
    await tester.pumpAndSettle();

    expect(at(r), '/chat/2');
    expect(fake.controller.isChannelListOpen, isFalse);
    expect(fake.opened[1]!.disposed, isTrue);
    expect(find.text('# random'), findsOneWidget);
  });
}

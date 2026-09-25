import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/chat_page.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/error_text.dart';

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

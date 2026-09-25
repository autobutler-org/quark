import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

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
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });
}

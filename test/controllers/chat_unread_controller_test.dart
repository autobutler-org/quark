import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_unread_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/services/events_service.dart';

/// Unread counts and read markers (#2424), over a fake Quark that answers
/// every marker with a count of zero.
void main() {
  late StreamController<FileEvent> events;
  late List<ChatChannel> channels;
  late List<String> marked;
  late int lists;
  Object? markFailWith;

  ChatUnreadController build() => ChatUnreadController(
    listChannels: () async {
      lists++;
      return channels;
    },
    markRead: (channelId, messageId) async {
      marked.add('$channelId $messageId');
      final error = markFailWith;
      if (error != null) throw error;
      return ChatReadMarker(
        channelId: channelId,
        lastReadMessageId: messageId,
        unreadCount: 0,
      );
    },
    markBranchRead: (rootId, messageId) async {
      marked.add('branch $rootId $messageId');
      return ChatReadMarker(
        channelId: 1,
        rootId: rootId,
        lastReadMessageId: messageId,
        unreadCount: 0,
      );
    },
    currentUserId: () => 7,
    events: events.stream,
  );

  FileEvent created(int channelId, {required int author}) => FileEvent(
    kind: 'chat_message_created',
    path: '',
    data: {
      'channelId': channelId,
      'messageId': 99,
      'message': {'id': 99, 'channelId': channelId, 'authorId': author},
    },
  );

  setUp(() {
    events = StreamController.broadcast();
    channels = const [
      ChatChannel(id: 1, name: 'general', unreadCount: 3),
      ChatChannel(id: 2, name: 'random'),
    ];
    marked = [];
    lists = 0;
    markFailWith = null;
  });

  tearDown(() => events.close());

  test('reads each channel\'s count off the channel list', () async {
    final unread = build();
    expect(unread.hasUnread, isFalse);

    await unread.refresh();

    expect(unread.countOf(1), 3);
    expect(unread.countOf(2), 0);
    expect(unread.countOf(404), 0);
    expect(unread.hasUnread, isTrue);
    unread.dispose();
  });

  test('a marker is sent once and clears the count', () async {
    final unread = build();
    await unread.refresh();
    var notified = 0;
    unread.addListener(() => notified++);

    await unread.markRead(1, 12);
    await unread.markRead(1, 12);

    expect(marked, ['1 12']);
    expect(unread.countOf(1), 0);
    expect(unread.hasUnread, isFalse);
    expect(notified, 1);
    unread.dispose();
  });

  test('a channel list restores the read marker it carries (#3543)', () async {
    final unread = build();
    unread.setChannels(const [
      ChatChannel(id: 1, name: 'general', lastReadMessageId: 5),
    ]);

    await unread.markRead(1, 4);
    await unread.markRead(1, 5);
    expect(marked, isEmpty);

    await unread.markRead(1, 6);
    expect(marked, ['1 6']);
    unread.dispose();
  });

  test('a marker never moves backward from this client', () async {
    final unread = build();

    await unread.markRead(1, 12);
    await unread.markRead(1, 9);
    await unread.markRead(1, 13);
    await unread.markRead(2, 4);

    expect(marked, ['1 12', '1 13', '2 4']);
    unread.dispose();
  });

  test('a marker that failed is sent again, and keeps the count', () async {
    final unread = build();
    await unread.refresh();
    markFailWith = Exception('offline');

    await unread.markRead(1, 12);
    expect(unread.countOf(1), 3);

    markFailWith = null;
    await unread.markRead(1, 12);
    expect(marked, ['1 12', '1 12']);
    expect(unread.countOf(1), 0);
    unread.dispose();
  });

  test('chat_read_marker_changed from another session clears the count, '
      'and nothing behind it is sent', () async {
    final unread = build();
    await unread.refresh();

    events.add(
      const FileEvent(
        kind: 'chat_read_marker_changed',
        path: '',
        data: {'channelId': 1, 'lastReadMessageId': 20, 'unreadCount': 0},
      ),
    );
    await pumpEventQueue();

    expect(unread.countOf(1), 0);
    expect(unread.hasUnread, isFalse);
    await unread.markRead(1, 20);
    await unread.markRead(1, 15);
    expect(marked, isEmpty);
    await unread.markRead(1, 21);
    expect(marked, ['1 21']);
    unread.dispose();
  });

  test('a malformed marker event is ignored', () async {
    final unread = build();
    await unread.refresh();

    events
      ..add(const FileEvent(kind: 'chat_read_marker_changed', path: ''))
      ..add(
        const FileEvent(
          kind: 'chat_read_marker_changed',
          path: '',
          data: {'unreadCount': 0},
        ),
      );
    await pumpEventQueue();

    expect(unread.countOf(1), 3);
    unread.dispose();
  });

  test('someone else\'s message adds one; your own does not', () async {
    final unread = build();
    await unread.refresh();

    events
      ..add(created(2, author: 8))
      ..add(created(2, author: 7));
    await pumpEventQueue();

    expect(unread.countOf(2), 1);
    expect(unread.countOf(1), 3);
    unread.dispose();
  });

  test('a deleted message, a channel change and a resync read the counts '
      'again', () async {
    final unread = build();
    await unread.refresh();
    expect(lists, 1);

    channels = const [ChatChannel(id: 1, name: 'general', unreadCount: 2)];
    events.add(
      const FileEvent(
        kind: 'chat_message_deleted',
        path: '',
        data: {'channelId': 1, 'messageId': 5},
      ),
    );
    await pumpEventQueue();
    expect(unread.countOf(1), 2);

    events
      ..add(const FileEvent(kind: 'chat_channel_changed', path: ''))
      ..add(const FileEvent(kind: 'resync', path: ''));
    await pumpEventQueue();
    expect(lists, 4);
    unread.dispose();
  });

  test('a list that will not load keeps the counts it had', () async {
    var fail = false;
    final unread = ChatUnreadController(
      listChannels: () async {
        if (fail) throw Exception('offline');
        return channels;
      },
      events: events.stream,
      currentUserId: () => 7,
    );
    await unread.refresh();
    fail = true;

    await unread.refresh();

    expect(unread.countOf(1), 3);
    unread.dispose();
  });

  test('the active channel\'s unread count stays 0 while it is open and '
      'focused', () async {
    final unread = build();
    await unread.refresh();
    expect(unread.countOf(1), 3);

    unread.setViewing(1, focused: true);
    expect(unread.countOf(1), 0);
    expect(unread.hasUnread, isFalse);

    events
      ..add(created(1, author: 8))
      ..add(created(1, author: 8))
      ..add(created(2, author: 8));
    await pumpEventQueue();

    expect(unread.countOf(1), 0);
    expect(unread.countOf(2), 1);
    expect(unread.hasUnread, isTrue);

    channels = const [
      ChatChannel(id: 1, name: 'general', unreadCount: 9),
      ChatChannel(id: 2, name: 'random', unreadCount: 4),
    ];
    await unread.refresh();
    expect(
      unread.countOf(1),
      0,
      reason: 'a refresh keeps the open channel clear',
    );
    expect(unread.countOf(2), 4);

    unread.setViewing(1, focused: false);
    expect(unread.countOf(1), 9);

    events.add(created(1, author: 8));
    await pumpEventQueue();
    expect(unread.countOf(1), 10);
    unread.dispose();
  });

  group('side conversations (#4349)', () {
    setUp(() {
      channels = const [
        ChatChannel(
          id: 1,
          name: 'general',
          unreadCount: 3,
          branchUnreadCount: 2,
          otherBranchUnreadCount: 4,
        ),
        ChatChannel(id: 2, name: 'random', otherBranchUnreadCount: 1),
        ChatChannel(id: 3, name: 'quiet'),
      ];
    });

    test(
      'involved branches add to the count; the others only to splits',
      () async {
        final unread = build();
        await unread.refresh();
        expect(unread.countOf(1), 5);
        expect(unread.countOf(2), 0);
        expect(unread.hasUnread, isTrue);
        expect(unread.splits, {
          1: (channel: 3, branches: 2, otherBranches: 4),
          2: (channel: 0, branches: 0, otherBranches: 1),
        });

        // The channel on screen reads zero, but its split stays for its chips.
        unread.setViewing(1, focused: true);
        expect(unread.countOf(1), 0);
        expect(unread.isViewing(1), isTrue);
        expect(unread.splits[1], (channel: 3, branches: 2, otherBranches: 4));
        unread.dispose();
      },
    );

    test('a reply, and a branch marker from another session, read the counts '
        'again', () async {
      final unread = build();
      await unread.refresh();
      expect(lists, 1);
      events.add(
        FileEvent(
          kind: 'chat_message_created',
          path: '',
          data: {
            'channelId': 1,
            'rootId': 5,
            'message': {'id': 99, 'channelId': 1, 'authorId': 8, 'rootId': 5},
          },
        ),
      );
      await pumpEventQueue();
      expect(lists, 2);
      expect(unread.countOf(1), 5, reason: 'a reply never adds one locally');

      events.add(
        const FileEvent(
          kind: 'chat_read_marker_changed',
          path: '',
          data: {
            'channelId': 1,
            'rootId': 5,
            'lastReadMessageId': 99,
            'unreadCount': 0,
          },
        ),
      );
      await pumpEventQueue();
      expect(lists, 3);
      expect(unread.countOf(1), 5, reason: 'the channel count is kept');
      unread.dispose();
    });

    test('a branch marker is sent once, forward only, then the counts are '
        'read', () async {
      final unread = build();
      await unread.markBranchRead(5, 10);
      await unread.markBranchRead(5, 10);
      await unread.markBranchRead(5, 9);
      await unread.markBranchRead(5, 11);
      expect(marked, ['branch 5 10', 'branch 5 11']);
      expect(lists, 2);
      unread.dispose();
    });
  });
}

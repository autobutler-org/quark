import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/chat_channel.dart';

/// The channel list's wire shape, with the unread count #2424 added.
void main() {
  test('reads lastReadMessageId, and zero from a Quark that sends none', () {
    final json = {'id': 4, 'name': 'family', 'lastReadMessageId': 5};

    expect(ChatChannel.fromJson(json).lastReadMessageId, 5);
    expect(
      ChatChannel.fromJson({'id': 4, 'name': 'family'}).lastReadMessageId,
      0,
    );
  });

  test('reads unreadCount, and zero from a Quark that sends none', () {
    final json = {'id': 4, 'name': 'family', 'unreadCount': 3};

    expect(ChatChannel.fromJson(json).unreadCount, 3);
    expect(ChatChannel.fromJson({'id': 4, 'name': 'family'}).unreadCount, 0);
  });

  // #2423: a direct message is kind dm, named for the other people in it.
  test('reads a direct message and names it for the others', () {
    final dm = ChatChannel.fromJson({
      'id': 9,
      'name': '',
      'kind': 'dm',
      'members': [
        {'id': 1, 'username': 'ada'},
        {'id': 2, 'username': 'bob'},
        {'id': 3, 'username': 'cy'},
      ],
    });

    expect(dm.isDirect, isTrue);
    expect(dm.directName(1), 'bob, cy');
    expect(dm.directName(2), 'ada, cy');
    expect(
      ChatChannel.fromJson({
        'id': 9,
        'kind': 'dm',
        'members': [
          {'id': 1, 'username': 'ada'},
        ],
      }).directName(1),
      'Only you',
    );
    expect(ChatChannel.fromJson({'id': 4, 'name': 'family'}).isDirect, isFalse);
  });

  test('reads a read marker', () {
    final marker = ChatReadMarker.fromJson({
      'channelId': 4,
      'lastReadMessageId': 123,
      'unreadCount': 0,
    });

    expect(marker.channelId, 4);
    expect(marker.lastReadMessageId, 123);
    expect(marker.unreadCount, 0);
  });
}

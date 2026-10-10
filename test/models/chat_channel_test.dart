import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/chat_channel.dart';

/// The channel list's wire shape, with the unread count #2424 added.
void main() {
  test('reads unreadCount, and zero from a Quark that sends none', () {
    final json = {'id': 4, 'name': 'family', 'unreadCount': 3};

    expect(ChatChannel.fromJson(json).unreadCount, 3);
    expect(ChatChannel.fromJson({'id': 4, 'name': 'family'}).unreadCount, 0);
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

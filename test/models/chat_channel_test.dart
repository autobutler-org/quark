import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark_widgets/quark_widgets.dart';

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

  // #2949: an anonymous channel carries the caller's pseudonym, and each
  // member its pseudonym and alias, real account or not.
  test('reads an anonymous channel and its members', () {
    final channel = ChatChannel.fromJson({
      'id': 5,
      'name': 'whispers',
      'anonymous': true,
      'selfId': -70,
    });
    expect(channel.anonymous, isTrue);
    expect(channel.selfId, -70);
    final plain = ChatChannel.fromJson({'id': 4, 'name': 'family'});
    expect(plain.anonymous, isFalse);
    expect(plain.selfId, isNull);

    final members = [
      ChatMember.fromJson({
        'userId': 7,
        'name': 'ada',
        'pseudonymId': -70,
        'alias': 'Anonymous 1',
        'permissions': ['read_messages', 'mention_everyone'],
      }),
      ChatMember.fromJson({
        'groupId': 3,
        'name': 'mods',
        'permissions': ['read_messages'],
        'users': [
          {'id': -80, 'username': 'Fox', 'pseudonymId': -80, 'alias': 'Fox'},
        ],
      }),
    ];
    expect(members[0].accountName, 'ada', reason: 'a privileged view');
    expect(members[1].users.single.accountName, isNull);
    expect(members.mentionNames, ['Anonymous 1', 'Fox']);
    expect(members.nameOfUser(-70), 'Anonymous 1');
    expect(members.nameOfUser(7), 'Anonymous 1');
    expect(members.boundIdOf(7), -70);
    expect(members.boundIdOf(9), 9);
    expect(members.userIdsHolding(ChatPermission.mentionEveryone), {-70});
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

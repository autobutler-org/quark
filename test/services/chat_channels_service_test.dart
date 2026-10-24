import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/chat_channels_service.dart';
import 'package:quark/utils/error_text.dart';

import '../support/fake_quark_http.dart';

/// The read-marker and unread-count wire shapes (#2424).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useFakeQuark();

  test('the channel list carries each unread count', () async {
    answer(200, {
      'channels': [
        {'id': 1, 'name': 'general', 'isDefault': true, 'unreadCount': 0},
        {'id': 4, 'name': 'family', 'unreadCount': 3},
      ],
    });

    final channels = await ChatChannelsService.listChannels();

    expect(channels.map((c) => c.unreadCount), [0, 3]);
  });

  test('markRead puts the message id and reads the marker back', () async {
    answer(200, {'channelId': 4, 'lastReadMessageId': 123, 'unreadCount': 0});

    final marker = await ChatChannelsService.markRead(4, 123);

    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/v0/chat/channels/4/read');
    expect(jsonDecode(requests.single.body), {'messageId': 123});
    expect(marker.lastReadMessageId, 123);
    expect(marker.unreadCount, 0);
  });

  test('a refused marker throws its status', () async {
    answer(404, <String, Object>{});

    await expectLater(
      ChatChannelsService.markRead(4, 999),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
    );
  });
}

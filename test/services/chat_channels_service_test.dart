import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/chat_channels_service.dart';
import 'package:quark/utils/error_text.dart';

/// The read-marker and unread-count wire shapes (#2424).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  void answer(int status, Object? body) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(body), status);
    });
  }

  setUp(requests.clear);
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

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

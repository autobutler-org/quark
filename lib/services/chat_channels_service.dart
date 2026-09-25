import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/chat_channel.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The chat channel routes the chat page reads (#2421): the channels the
/// account belongs to, and one channel's members.
class ChatChannelsService with AuthenticatedService {
  ChatChannelsService._();

  /// The one instance, for the [AuthenticatedService] helpers.
  static final ChatChannelsService instance = ChatChannelsService._();

  /// The channels the signed-in account belongs to, `general` first.
  static Future<List<ChatChannel>> listChannels() async {
    final response = await instance.authenticatedGet(_uri(''));
    _check(response, 'list chat channels');
    return [
      for (final c in _json(response)['channels'] as List? ?? const [])
        ChatChannel.fromJson(c as Map<String, dynamic>),
    ];
  }

  /// Channel [channelId]'s members: accounts, and groups with their accounts.
  static Future<List<ChatMember>> listMembers(int channelId) async {
    final response = await instance.authenticatedGet(
      _uri('/$channelId/members'),
    );
    _check(response, 'list members of channel $channelId');
    return [
      for (final m in _json(response)['members'] as List? ?? const [])
        ChatMember.fromJson(m as Map<String, dynamic>),
    ];
  }

  static Uri _uri(String suffix) =>
      apiBaseUri.resolve('/api/v0/chat/channels$suffix');

  static Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

  static void _check(http.Response response, String context) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    Object? error;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) error = decoded['error'];
    } on FormatException {
      error = null;
    }
    throwApiError(status, error, context);
  }
}

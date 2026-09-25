import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/chat_channel_keys.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// A channel's members after a change, and the event the Quark recorded for
/// it, which the account that made the change signs.
typedef ChatMembersChange = ({
  List<ChatMember> members,
  ChatChannelEvent? event,
});

/// The chat channel routes (#2421, #2422): listing, creating, renaming and
/// deleting channels, and reading and changing who is in one.
///
/// A refusal the Quark words itself, such as "this would leave the channel
/// without an owner", reaches the user as written. A name already taken is
/// thrown as its bare 409, for `Errors.chatChannel` to phrase.
class ChatChannelsService with AuthenticatedService {
  ChatChannelsService._();

  /// The one instance, for the [AuthenticatedService] helpers.
  static final ChatChannelsService instance = ChatChannelsService._();

  /// The channels the signed-in account belongs to, `general` first.
  static Future<List<ChatChannel>> listChannels() => _list(all: false);

  /// For an admin: their channels, then every channel they are not in, which
  /// carries no level. Anyone else is refused.
  static Future<List<ChatChannel>> listAllChannels() => _list(all: true);

  /// Creates channel [name] with [topic], owned by the signed-in account.
  static Future<ChatChannel> createChannel(String name, String topic) async {
    final response = await instance.authenticatedPost(
      _uri(''),
      headers: _jsonHeaders,
      body: jsonEncode({'name': name, 'topic': topic}),
    );
    _checkName(response, 'create a chat channel');
    return ChatChannel.fromJson(_json(response));
  }

  /// Renames channel [channelId] to [name] and sets its [topic].
  static Future<ChatChannel> updateChannel(
    int channelId, {
    required String name,
    required String topic,
  }) async {
    final response = await instance.authenticatedPatch(
      _uri('/$channelId'),
      headers: _jsonHeaders,
      body: jsonEncode({'name': name, 'topic': topic}),
    );
    _checkName(response, 'update chat channel $channelId');
    return ChatChannel.fromJson(_json(response));
  }

  /// Deletes channel [channelId] with its messages and keys.
  static Future<void> deleteChannel(int channelId) async {
    final response = await instance.authenticatedDelete(_uri('/$channelId'));
    _check(response, 'delete chat channel $channelId');
  }

  /// Channel [channelId]'s members: accounts, and groups with their accounts.
  static Future<List<ChatMember>> listMembers(int channelId) async {
    final response = await instance.authenticatedGet(
      _uri('/$channelId/members'),
    );
    _check(response, 'list members of channel $channelId');
    return _members(response).members;
  }

  /// Gives account [userId] or group [groupId] [level] on channel
  /// [channelId]: `read`, `write` or `owner`.
  static Future<ChatMembersChange> setMember(
    int channelId, {
    int? userId,
    int? groupId,
    required String level,
  }) async {
    final response = await instance.authenticatedPut(
      _uri('/$channelId/members'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'userId': ?userId,
        'groupId': ?groupId,
        'level': level,
      }),
    );
    _check(response, 'set a member of channel $channelId');
    return _members(response);
  }

  /// Removes account [userId]'s or group [groupId]'s row from channel
  /// [channelId]. The signed-in account removing its own row leaves.
  static Future<ChatMembersChange> removeMember(
    int channelId, {
    int? userId,
    int? groupId,
  }) async {
    final response = await instance.authenticatedDelete(
      _uri('/$channelId/members'),
      headers: _jsonHeaders,
      body: jsonEncode({'userId': ?userId, 'groupId': ?groupId}),
    );
    _check(response, 'remove a member of channel $channelId');
    return _members(response);
  }

  static Future<List<ChatChannel>> _list({required bool all}) async {
    final uri = _uri('');
    final response = await instance.authenticatedGet(
      all ? uri.replace(queryParameters: {'all': '1'}) : uri,
    );
    _check(response, 'list chat channels');
    return [
      for (final c in _json(response)['channels'] as List? ?? const [])
        ChatChannel.fromJson(c as Map<String, dynamic>),
    ];
  }

  static const _jsonHeaders = {'Content-Type': 'application/json'};

  static Uri _uri(String suffix) =>
      apiBaseUri.resolve('/api/v0/chat/channels$suffix');

  static Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

  static ChatMembersChange _members(http.Response response) {
    final json = _json(response);
    final event = json['event'];
    return (
      members: [
        for (final m in json['members'] as List? ?? const [])
          ChatMember.fromJson(m as Map<String, dynamic>),
      ],
      event: event is Map<String, dynamic>
          ? ChatChannelEvent.fromJson(event)
          : null,
    );
  }

  /// [_check], but a 409 stays a bare [ApiException] so the name-taken copy
  /// comes from `Errors`.
  static void _checkName(http.Response response, String context) {
    if (response.statusCode == 409) throw ApiException(409, context);
    _check(response, context);
  }

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

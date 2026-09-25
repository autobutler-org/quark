import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quark/models/chat_message.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The chat message routes (#2418): paging a channel's messages, posting
/// one, and deleting one.
///
/// Everything here is ciphertext; `ChatMessagesController` encrypts and
/// decrypts.
class ChatMessagesService with AuthenticatedService {
  ChatMessagesService._();

  /// The one instance, for the [AuthenticatedService] helpers.
  static final ChatMessagesService instance = ChatMessagesService._();

  /// The Quark's cap on one message's ciphertext.
  static const maxCiphertextBytes = 16 << 10;

  /// The most messages one page returns.
  static const maxPage = 200;

  /// A page of channel [channelId]'s messages, oldest first. With [after],
  /// the page starts after that id (0 is the beginning); otherwise it ends
  /// before [before], or at the newest.
  static Future<List<ChatMessage>> fetchMessages(
    int channelId, {
    int? before,
    int? after,
    int? limit,
  }) async {
    final response = await instance.authenticatedGet(
      _channelUri(channelId, {
        if (before != null) 'before': '$before',
        if (after != null) 'after': '$after',
        if (limit != null) 'limit': '$limit',
      }),
    );
    _check(response, 'fetch messages of channel $channelId');
    return [
      for (final m in _json(response)['messages'] as List? ?? const [])
        ChatMessage.fromJson(m as Map<String, dynamic>),
    ];
  }

  /// Posts [ciphertext], encrypted under [keyVersion], and returns the stored
  /// message.
  static Future<ChatMessage> postMessage(
    int channelId,
    int keyVersion,
    Uint8List ciphertext,
  ) async {
    final response = await instance.authenticatedPost(
      _channelUri(channelId),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'keyVersion': keyVersion,
        'ciphertext': base64Encode(ciphertext),
      }),
    );
    _check(response, 'post to channel $channelId');
    return ChatMessage.fromJson(_json(response));
  }

  /// Deletes message [messageId] and returns its tombstone.
  static Future<ChatMessage> deleteMessage(int messageId) async {
    final response = await instance.authenticatedDelete(
      apiBaseUri.resolve('/api/v0/chat/messages/$messageId'),
    );
    _check(response, 'delete message $messageId');
    return ChatMessage.fromJson(_json(response));
  }

  static Uri _channelUri(int channelId, [Map<String, String>? query]) =>
      apiBaseUri
          .resolve('/api/v0/chat/channels/$channelId/messages')
          .replace(
            queryParameters: query == null || query.isEmpty ? null : query,
          );

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

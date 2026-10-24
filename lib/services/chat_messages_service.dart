import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quark/models/chat_message.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';

/// The chat message routes (#2418): paging a channel's messages, posting
/// one, and deleting one; and reacting to one and taking a reaction back
/// (#2426).
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
    throwUnlessOk(response, 'fetch messages of channel $channelId');
    return [
      for (final m in _json(response)['messages'] as List? ?? const [])
        ChatMessage.fromJson(m as Map<String, dynamic>),
    ];
  }

  /// Posts [ciphertext], encrypted under [keyVersion], and returns the stored
  /// message. A [clientMessageId] the Quark already has from this account in
  /// this channel returns that message instead of storing a second one.
  static Future<ChatMessage> postMessage(
    int channelId,
    int keyVersion,
    Uint8List ciphertext, {
    String? clientMessageId,
  }) async {
    final response = await instance.authenticatedPost(
      _channelUri(channelId),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'keyVersion': keyVersion,
        'ciphertext': base64Encode(ciphertext),
        'clientMessageId': ?clientMessageId,
      }),
    );
    throwUnlessOk(response, 'post to channel $channelId');
    return ChatMessage.fromJson(_json(response));
  }

  /// Deletes message [messageId] and returns its tombstone.
  static Future<ChatMessage> deleteMessage(int messageId) async {
    final response = await instance.authenticatedDelete(
      apiBaseUri.resolve('/api/v0/chat/messages/$messageId'),
    );
    throwUnlessOk(response, 'delete message $messageId');
    return ChatMessage.fromJson(_json(response));
  }

  /// Adds [ciphertext], a reaction encrypted under [keyVersion], to message
  /// [messageId] and returns the stored reaction.
  static Future<ChatReaction> addReaction(
    int messageId,
    int keyVersion,
    Uint8List ciphertext,
  ) async {
    final response = await instance.authenticatedPost(
      apiBaseUri.resolve('/api/v0/chat/messages/$messageId/reactions'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'keyVersion': keyVersion,
        'ciphertext': base64Encode(ciphertext),
      }),
    );
    throwUnlessOk(response, 'react to message $messageId');
    return ChatReaction.fromJson(_json(response));
  }

  /// Removes reaction [reactionId].
  static Future<void> deleteReaction(int reactionId) async {
    final response = await instance.authenticatedDelete(
      apiBaseUri.resolve('/api/v0/chat/reactions/$reactionId'),
    );
    throwUnlessOk(response, 'remove reaction $reactionId');
  }

  static Uri _channelUri(int channelId, [Map<String, String>? query]) =>
      apiBaseUri
          .resolve('/api/v0/chat/channels/$channelId/messages')
          .replace(
            queryParameters: query == null || query.isEmpty ? null : query,
          );

  static Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;
}

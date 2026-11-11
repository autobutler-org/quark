import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:quark/models/chat_message.dart';
import 'package:quark/models/chat_poll.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';

/// The chat message routes (#2418): paging a channel's messages, posting
/// one, and deleting one; reacting to one and taking a reaction back
/// (#2426); posting, answering and closing a poll (#3894); and uploading
/// and downloading an attachment's ciphertext (#2425).
///
/// Everything here is ciphertext; `ChatMessagesController` encrypts and
/// decrypts. The file key stays inside the message.
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
  /// this channel returns that message instead of storing a second one. With
  /// [poll], the message is a poll with its settings. [attachmentIds], when
  /// passed, names files already uploaded to this channel; the Quark binds
  /// them to the message. The name, the media type and the key stay inside
  /// [ciphertext].
  static Future<ChatMessage> postMessage(
    int channelId,
    int keyVersion,
    Uint8List ciphertext, {
    String? clientMessageId,
    List<String>? attachmentIds,
    ChatPoll? poll,
  }) async {
    final response = await instance.authenticatedPost(
      _channelUri(channelId),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
        postMessageBody(
          keyVersion: keyVersion,
          ciphertext: ciphertext,
          clientMessageId: clientMessageId,
          attachmentIds: attachmentIds,
          poll: poll,
        ),
      ),
    );
    throwUnlessOk(response, 'post to channel $channelId');
    return ChatMessage.fromJson(_json(response));
  }

  /// The JSON object [postMessage] sends.
  ///
  /// [attachmentIds] is left out when it is null, so a post that names no
  /// files has the same body as before. Each id is 64 lowercase hex
  /// characters. The Quark reads them to bind uploads; it does not read
  /// [ciphertext].
  static Map<String, Object?> postMessageBody({
    required int keyVersion,
    required Uint8List ciphertext,
    String? clientMessageId,
    List<String>? attachmentIds,
    ChatPoll? poll,
  }) => {
    'keyVersion': keyVersion,
    'ciphertext': base64Encode(ciphertext),
    'clientMessageId': ?clientMessageId,
    'attachmentIds': ?attachmentIds,
    'poll': ?poll?.settingsJson(),
  };

  /// Uploads [body] as attachment [id] on channel [channelId].
  ///
  /// [body] is a `Stream<List<int>>` or a `List<int>` of ciphertext.
  /// `PUT /api/v0/chat/channels/{channelId}/attachments/{id}` with
  /// `application/octet-stream`. A list is sent in slices: a [Uint8List] is
  /// viewed, not copied, and any other list is copied one slice at a time, so
  /// the file is not held in a second buffer. Returns the stored `byteSize`.
  static Future<int> putAttachment(
    int channelId,
    String id,
    Object body,
  ) async {
    final request =
        _UploadRequest('PUT', _attachmentUri(channelId, id), _uploadBody(body))
          ..headers['Content-Type'] = 'application/octet-stream'
          ..contentLength = body is List<int> ? body.length : null;
    final response = await instance.authenticatedSend(request);
    // The answer is the stored id and byte size, a few dozen bytes, not the
    // file that was just uploaded.
    final wrapped = await http.Response.fromStream(response);
    // A 5xx carries a diagnostic, host paths included, not copy (#4050).
    throwUnlessOk(
      wrapped,
      'upload attachment $id to channel $channelId',
      clientErrorsOnly: true,
    );
    final decoded = jsonDecode(wrapped.body);
    final size = decoded is Map<String, dynamic> ? decoded['byteSize'] : null;
    if (size is! int) {
      throw const FormatException('attachment upload answered with no size');
    }
    return size;
  }

  /// Downloads the ciphertext of attachment [id] on channel [channelId].
  ///
  /// `GET` on the same path as [putAttachment]. The body is not collected
  /// into one buffer. Pass [sink] and each chunk is added to it; the returned
  /// stream is then empty, because the bytes already went to [sink]. Without
  /// [sink], the returned stream is the body. The caller must read or drain
  /// it. A test may collect a small file from that stream.
  static Future<Stream<List<int>>> getAttachment(
    int channelId,
    String id, {
    StreamSink<List<int>>? sink,
  }) async {
    final response = await instance.authenticatedSend(
      http.Request('GET', _attachmentUri(channelId, id)),
    );
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      final wrapped = await http.Response.fromStream(response);
      throwUnlessOk(wrapped, 'download attachment $id of channel $channelId');
    }
    if (sink != null) {
      await for (final chunk in response.stream) {
        sink.add(chunk);
      }
      return const Stream<List<int>>.empty();
    }
    return response.stream;
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
      _messageUri(messageId, 'reactions'),
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

  /// Stores [ciphertext], this account's padded answer encrypted under
  /// [keyVersion], as its answer to poll [messageId], and returns it. The
  /// Quark refuses a closed poll, and a second answer to one that doesn't
  /// allow changing it, with a 409 and a sentence of its own.
  static Future<ChatPollResponse> answerPoll(
    int messageId,
    int keyVersion,
    Uint8List ciphertext,
  ) async {
    final response = await instance.authenticatedPut(
      _messageUri(messageId, 'answer'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'keyVersion': keyVersion,
        'ciphertext': base64Encode(ciphertext),
      }),
    );
    throwUnlessOk(response, 'answer poll $messageId');
    return ChatPollResponse.fromJson(_json(response));
  }

  /// The answers to poll [messageId] this account may see, oldest first, or
  /// not in arrival order when the poll is anonymous.
  static Future<List<ChatPollResponse>> fetchPollAnswers(int messageId) async {
    final response = await instance.authenticatedGet(
      _messageUri(messageId, 'answers'),
    );
    throwUnlessOk(response, 'fetch answers of poll $messageId');
    return [
      for (final a in _json(response)['answers'] as List? ?? const [])
        ChatPollResponse.fromJson(a as Map<String, dynamic>),
    ];
  }

  /// Closes poll [messageId], which only its author may, and returns its
  /// settings and state, without answers.
  static Future<ChatPoll> closePoll(int messageId) async {
    final response = await instance.authenticatedPost(
      _messageUri(messageId, 'close'),
    );
    throwUnlessOk(response, 'close poll $messageId');
    return ChatPoll.fromJson(_json(response));
  }

  static Uri _messageUri(int messageId, String action) =>
      apiBaseUri.resolve('/api/v0/chat/messages/$messageId/$action');

  static Uri _channelUri(int channelId, [Map<String, String>? query]) =>
      apiBaseUri
          .resolve('/api/v0/chat/channels/$channelId/messages')
          .replace(
            queryParameters: query == null || query.isEmpty ? null : query,
          );

  static Uri _attachmentUri(int channelId, String id) =>
      apiBaseUri.resolve('/api/v0/chat/channels/$channelId/attachments/$id');

  static Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;
}

/// How many bytes of a list [ChatMessagesService.putAttachment] hands the
/// socket at a time. A slice is a view when the bytes are a [Uint8List].
const int _uploadChunkBytes = 64 * 1024;

/// PUT body that is already a stream. [finalize] does not copy it; the HTTP
/// client reads [body].
class _UploadRequest extends http.BaseRequest {
  _UploadRequest(super.method, super.url, this.body);

  final Stream<List<int>> body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(body);
  }
}

Stream<List<int>> _uploadBody(Object body) {
  if (body is Stream<List<int>>) return body;
  if (body is Uint8List) return _views(body);
  if (body is List<int>) return _sliceCopies(body);
  throw ArgumentError.value(
    body,
    'body',
    'pass a Stream<List<int>> or a List<int>',
  );
}

Stream<List<int>> _views(Uint8List bytes) {
  if (bytes.isEmpty) return const Stream<List<int>>.empty();
  final slices = <Uint8List>[];
  for (var offset = 0; offset < bytes.length; offset += _uploadChunkBytes) {
    final end = offset + _uploadChunkBytes < bytes.length
        ? offset + _uploadChunkBytes
        : bytes.length;
    slices.add(Uint8List.sublistView(bytes, offset, end));
  }
  return Stream.fromIterable(slices);
}

/// One slice at a time, so [bytes] is not copied into a second full buffer.
Stream<List<int>> _sliceCopies(List<int> bytes) async* {
  for (var offset = 0; offset < bytes.length; offset += _uploadChunkBytes) {
    final end = offset + _uploadChunkBytes < bytes.length
        ? offset + _uploadChunkBytes
        : bytes.length;
    yield bytes.sublist(offset, end);
  }
}

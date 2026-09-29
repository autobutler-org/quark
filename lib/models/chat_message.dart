import 'dart:convert';
import 'dart:typed_data';

import 'package:quark/models/chat_channel_keys.dart';

/// One chat message as the Quark stores it (#2418): who sent it, when, under
/// which channel key version, and ciphertext the Quark can't open.
///
/// [ciphertext] is `nonce || XChaCha20-Poly1305 output`, with the channel id
/// and key version bound as additional data (`ChatCrypto.messageAad`). A
/// deleted message is a tombstone: [deletedAt] set and no ciphertext.
class ChatMessage {
  /// Builds a message explicitly; tests use it.
  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.authorId,
    required this.keyVersion,
    required this.ciphertext,
    required this.createdAt,
    this.editedAt,
    this.deletedAt,
  });

  /// Increasing within the Quark, across every channel.
  final int id;

  /// The channel it was posted in.
  final int channelId;

  /// Who sent it, 0 once that account is deleted.
  final int authorId;

  /// The channel key version it was encrypted under.
  final int keyVersion;

  /// The encrypted body, null once deleted.
  final Uint8List? ciphertext;

  /// When the Quark stored it.
  final DateTime createdAt;

  /// When it was last edited, if ever.
  final DateTime? editedAt;

  /// When it was deleted, if it was.
  final DateTime? deletedAt;

  /// Whether this is a tombstone.
  bool get isDeleted => deletedAt != null;

  /// This message as a tombstone, for a `chat_message_deleted` event, which
  /// carries only the id.
  ChatMessage tombstone(DateTime at) => ChatMessage(
    id: id,
    channelId: channelId,
    authorId: authorId,
    keyVersion: keyVersion,
    ciphertext: null,
    createdAt: createdAt,
    editedAt: editedAt,
    deletedAt: deletedAt ?? at,
  );

  /// Reads one message as the API or a `chat_message_created` event sends it.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime? time(String key) {
      final value = json[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    final ciphertext = json['ciphertext'] as String?;
    return ChatMessage(
      id: (json['id'] as num).toInt(),
      channelId: (json['channelId'] as num).toInt(),
      authorId: (json['authorId'] as num?)?.toInt() ?? 0,
      keyVersion: (json['keyVersion'] as num).toInt(),
      ciphertext: ciphertext == null ? null : base64Decode(ciphertext),
      createdAt: DateTime.parse(json['createdAt'] as String),
      editedAt: time('editedAt'),
      deletedAt: time('deletedAt'),
    );
  }
}

/// What the client could make of a [ChatMessage].
enum ChatMessageState {
  /// Decrypted; the text is there.
  ready,

  /// This account has no grant of the message's key version yet, so it waits
  /// for a member to share it, and opens on its own when one does.
  waiting,

  /// The key is there but the ciphertext doesn't open under it: tampered
  /// with, or moved from another channel or version.
  unreadable,

  /// A tombstone.
  deleted,
}

/// One line of a channel's timeline: a message, or a membership or key event
/// shown as a system line.
///
/// `ChatMessagesController.entries` merges both, oldest first.
sealed class ChatTimelineEntry {
  const ChatTimelineEntry();

  /// When the Quark recorded it; the timeline's order.
  DateTime get createdAt;
}

/// A message in the timeline, with its plaintext when [state] is
/// [ChatMessageState.ready]. The text lives only in memory.
final class ChatTimelineMessage extends ChatTimelineEntry {
  /// Wraps [message] with what the client made of it.
  const ChatTimelineMessage({
    required this.message,
    required this.state,
    this.text,
  });

  /// The stored message.
  final ChatMessage message;

  /// Whether [text] is there, and why not.
  final ChatMessageState state;

  /// The decrypted body, only when [state] is [ChatMessageState.ready].
  final String? text;

  @override
  DateTime get createdAt => message.createdAt;
}

/// A channel event in the timeline, shown as a system line.
final class ChatTimelineSystem extends ChatTimelineEntry {
  /// Wraps [event] with whether its actor's signature checks out.
  const ChatTimelineSystem({required this.event, required this.isVerified});

  /// The membership or key event.
  final ChatChannelEvent event;

  /// Whether the actor signed it and the signature verifies. An unsigned
  /// event, such as an admin adding themselves, is shown as unverified.
  final bool isVerified;

  /// The inverse of [isVerified], as `ChatMessageItem.isUnverified` reads.
  bool get isUnverified => !isVerified;

  @override
  DateTime get createdAt => event.createdAt;
}

import 'package:flutter/foundation.dart';

/// What a [ChatMessageItem] is, which decides how a message list draws it.
enum ChatMessageKind {
  /// Something a person wrote, with its decrypted [ChatMessageItem.body].
  text,

  /// A line the channel itself records: a key rotation, or someone joining or
  /// leaving. Drawn as one line with a glyph and its time, with no author
  /// header.
  system,

  /// A message that arrived before the key that decrypts it. Drawn as a
  /// placeholder under its author.
  waitingForKey,

  /// A message its author deleted. Drawn as a tombstone under its author.
  deleted,
}

/// One line in a chat channel as the chat widgets need it.
///
/// The package's own view of a message, so no widget imports the app's model.
/// The body is plaintext: decrypting it is the caller's job, and a message
/// that cannot be decrypted yet is [ChatMessageKind.waitingForKey].
@immutable
class ChatMessageItem {
  /// Creates a message value.
  const ChatMessageItem({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.sentAt,
    this.body = '',
    this.kind = ChatMessageKind.text,
    this.isUnverified = false,
  });

  /// The message's id on the Quark, and what keys and callbacks carry.
  final String id;

  /// The id of the account that sent it, handed to the avatar builder.
  final String authorId;

  /// The name shown above the author's messages.
  final String authorName;

  /// When the message was sent, in the time zone it should be shown in.
  final DateTime sentAt;

  /// The text of a [ChatMessageKind.text] or [ChatMessageKind.system] line.
  /// Ignored for the other kinds, which draw their own copy.
  final String body;

  /// What the message is, which decides how it is drawn.
  final ChatMessageKind kind;

  /// Whether the signature on this line could not be checked, such as a
  /// membership change nobody vouched for. Drawn in the warning color.
  final bool isUnverified;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageItem &&
          other.id == id &&
          other.authorId == authorId &&
          other.authorName == authorName &&
          other.sentAt == sentAt &&
          other.body == body &&
          other.kind == kind &&
          other.isUnverified == isUnverified;

  @override
  int get hashCode =>
      Object.hash(id, authorId, authorName, sentAt, body, kind, isUnverified);
}

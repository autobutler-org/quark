import 'package:flutter/foundation.dart';

/// Whether a [ChatAttachmentItem] is a photo, a video, or any other file.
///
/// The caller derives this from the media type. The widgets do not sniff
/// bytes, because the package never holds the file.
enum ChatAttachmentKind {
  /// A photo, drawn from [ChatAttachmentTile]'s thumbnail builder.
  image,

  /// A video. The tile shows a play control and does not play it.
  video,

  /// Anything else, drawn as a name and a size.
  file,
}

/// One file attached to a chat message, as the chat widgets draw it.
///
/// No bytes: a thumbnail is a builder on the message list, and opening or
/// playing the file is a callback. [size] is the plaintext size in bytes.
@immutable
class ChatAttachmentItem {
  /// Creates an attachment value.
  const ChatAttachmentItem({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.kind,
  });

  /// The attachment's id, and what keys and callbacks carry.
  final String id;

  /// The file name shown on the tile.
  final String name;

  /// The media type, for example `image/jpeg`. The caller used it to pick
  /// [kind].
  final String mime;

  /// The plaintext size in bytes.
  final int size;

  /// How the tile draws this file.
  final ChatAttachmentKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatAttachmentItem &&
          other.id == id &&
          other.name == name &&
          other.mime == mime &&
          other.size == size &&
          other.kind == kind;

  @override
  int get hashCode => Object.hash(id, name, mime, size, kind);
}

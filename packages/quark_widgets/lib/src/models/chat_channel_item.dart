import 'package:flutter/foundation.dart';

import 'chat_permission.dart';

/// One chat channel as the chat widgets need it: its id, its name, and
/// whether it is shared with only some people.
///
/// The package's own view of a channel, so no widget imports the app's model.
/// Callbacks come back out with the [id].
@immutable
class ChatChannelItem {
  /// Creates a channel value.
  const ChatChannelItem({
    required this.id,
    required this.name,
    this.isPrivate = false,
    this.permissions,
    this.unreadCount = 0,
  });

  /// The channel's id on the Quark, and what callbacks carry.
  final String id;

  /// The channel's name, shown without a leading `#`.
  final String name;

  /// Whether the channel is shared with only some people rather than with
  /// everyone on the Quark. Private channels show a lock.
  final bool isPrivate;

  /// What the signed-in account may do in the channel, shown under its name
  /// as a preset or Custom. Null shows nothing.
  final Set<ChatPermission>? permissions;

  /// Messages from other people since this account last read the channel;
  /// 0 shows nothing.
  final int unreadCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatChannelItem &&
          other.id == id &&
          other.name == name &&
          other.isPrivate == isPrivate &&
          other.unreadCount == unreadCount &&
          setEquals(other.permissions, permissions);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    isPrivate,
    unreadCount,
    Object.hashAllUnordered(permissions ?? const <ChatPermission>{}),
  );
}

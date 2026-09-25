import 'package:flutter/foundation.dart';

import 'access_level.dart';

/// One member of a chat channel as the chat widgets need it: an account, or a
/// group the channel is shared with and the accounts in it.
///
/// The package's own view of a member, so no widget imports the app's model.
/// Callbacks come back out with the [id].
@immutable
class ChatMemberItem {
  /// Creates a member value.
  const ChatMemberItem({
    required this.id,
    required this.name,
    this.isGroup = false,
    this.level,
    this.members = const [],
  });

  /// The member's id, unique across accounts and groups in one list, and what
  /// callbacks and the avatar builder carry.
  final String id;

  /// The account or group name.
  final String name;

  /// Whether this is a group, whose [members] can be expanded under it.
  final bool isGroup;

  /// What the member may do in the channel, shown under the name. Null shows
  /// nothing.
  final AccessLevel? level;

  /// The accounts in a group, in the order they are shown. Empty for an
  /// account.
  final List<ChatMemberItem> members;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMemberItem &&
          other.id == id &&
          other.name == name &&
          other.isGroup == isGroup &&
          other.level == level &&
          listEquals(other.members, members);

  @override
  int get hashCode =>
      Object.hash(id, name, isGroup, level, Object.hashAll(members));
}

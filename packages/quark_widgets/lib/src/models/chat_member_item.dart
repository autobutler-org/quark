import 'package:flutter/foundation.dart';

import 'chat_permission.dart';

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
    this.permissions,
    this.members = const [],
  });

  /// The member's id, unique across accounts and groups in one list, and what
  /// callbacks and the avatar builder carry.
  final String id;

  /// The account or group name.
  final String name;

  /// Whether this is a group, whose [members] can be expanded under it.
  final bool isGroup;

  /// What this member's row lets them do in the channel, shown under the name
  /// as its preset's name, or Custom. Null shows nothing, as for an account
  /// listed under its group.
  final Set<ChatPermission>? permissions;

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
          setEquals(other.permissions, permissions) &&
          listEquals(other.members, members);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    isGroup,
    Object.hashAllUnordered(permissions ?? const <ChatPermission>{}),
    Object.hashAll(members),
  );
}

/// One thing a member of a chat channel may do (#2415).
///
/// A member holds a set of these, not a level: they don't sit on one axis,
/// so someone may post without deleting other people's messages, or add
/// members without renaming the channel. [id] is the name the Quark uses for
/// it, and what keys built from a permission carry.
///
/// Seeing a channel is not a permission: any non-empty set sees it. A set
/// with a management permission but no [readMessages] is a delegated
/// manager, who runs the channel without being in the conversation.
///
/// Some permissions need another one first ([requires]), and a set that lacks
/// a prerequisite is refused. [withPrerequisites] and [withoutDependents]
/// keep a set whole when one permission is ticked or cleared.
enum ChatPermission {
  /// See the channel and read it: its name, topic, members, history and new
  /// messages. The only permission that comes with the channel key.
  readMessages(
    'read_messages',
    'Read messages',
    'See the channel and read its messages',
  ),

  /// Post a message.
  sendMessages('send_messages', 'Send messages', 'Post messages'),

  /// React to a message.
  addReactions('add_reactions', 'Add reactions', 'React to messages'),

  /// Delete other people's messages. Everyone may delete their own.
  deleteMessages(
    'delete_messages',
    'Delete messages',
    "Delete other people's messages",
  ),

  /// Rename the channel, change its topic, and delete it.
  manageChannel(
    'manage_channel',
    'Manage channel',
    'Rename the channel, change its topic, delete it',
  ),

  /// Add and remove members and change what they may do.
  manageMembers(
    'manage_members',
    'Manage members',
    'Add and remove members and change their permissions',
  );

  const ChatPermission(this.id, this.label, this.description);

  /// The permission's name on the Quark, such as `send_messages`.
  final String id;

  /// The words the chat widgets show for it.
  final String label;

  /// One line saying what it allows.
  final String description;

  /// The permissions this one needs. A set holding this one without them is
  /// incoherent.
  Set<ChatPermission> get requires => switch (this) {
    sendMessages || addReactions || deleteMessages => const {readMessages},
    readMessages || manageChannel || manageMembers => const {},
  };

  /// The permission named [id], or null for a name this version doesn't
  /// know.
  static ChatPermission? byId(String id) {
    for (final permission in values) {
      if (permission.id == id) return permission;
    }
    return null;
  }

  /// [permissions] with every prerequisite of every member added, so ticking
  /// `send_messages` also ticks `read_messages`.
  static Set<ChatPermission> withPrerequisites(
    Set<ChatPermission> permissions,
  ) {
    final result = {...permissions};
    var grew = true;
    while (grew) {
      final before = result.length;
      result.addAll([for (final p in result.toList()) ...p.requires]);
      grew = result.length != before;
    }
    return Set.unmodifiable(result);
  }

  /// [permissions] without [removed] and without everything that needs it,
  /// so clearing `read_messages` also clears `send_messages`,
  /// `add_reactions` and `delete_messages`, and leaves the management
  /// permissions, which need nothing.
  static Set<ChatPermission> withoutDependents(
    Set<ChatPermission> permissions,
    ChatPermission removed,
  ) {
    final gone = {removed};
    var grew = true;
    while (grew) {
      final before = gone.length;
      gone.addAll([
        for (final p in permissions)
          if (p.requires.any(gone.contains)) p,
      ]);
      grew = gone.length != before;
    }
    return Set.unmodifiable(permissions.difference(gone));
  }
}

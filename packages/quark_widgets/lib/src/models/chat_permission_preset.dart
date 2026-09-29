import 'package:flutter/foundation.dart';

import 'chat_permission.dart';

/// A named set of [ChatPermission]s the chat widgets offer as a shortcut
/// (#2415).
///
/// Presets are a picker convenience only: a member always holds a full set,
/// and a set that matches no preset exactly is shown as **Custom**
/// ([labelOf]).
enum ChatPermissionPreset {
  /// See the channel and read it.
  viewer('Viewer', {ChatPermission.readMessages}),

  /// A viewer who also posts and reacts.
  member('Member', {
    ChatPermission.readMessages,
    ChatPermission.sendMessages,
    ChatPermission.addReactions,
  }),

  /// A member who also deletes other people's messages and manages members.
  moderator('Moderator', {
    ChatPermission.readMessages,
    ChatPermission.sendMessages,
    ChatPermission.addReactions,
    ChatPermission.deleteMessages,
    ChatPermission.manageMembers,
  }),

  /// Everything.
  owner('Owner', {
    ChatPermission.readMessages,
    ChatPermission.sendMessages,
    ChatPermission.addReactions,
    ChatPermission.deleteMessages,
    ChatPermission.manageChannel,
    ChatPermission.manageMembers,
  });

  const ChatPermissionPreset(this.label, this.permissions);

  /// The preset's name as the chat widgets show it.
  final String label;

  /// The exact set the preset stands for.
  final Set<ChatPermission> permissions;

  /// What a set that matches no preset is called.
  static const String customLabel = 'Custom';

  /// The preset whose set is exactly [permissions], or null when it is a
  /// custom set.
  static ChatPermissionPreset? of(Set<ChatPermission> permissions) {
    for (final preset in values) {
      if (setEquals(preset.permissions, permissions)) return preset;
    }
    return null;
  }

  /// The preset name for [permissions], or [customLabel].
  static String labelOf(Set<ChatPermission> permissions) =>
      of(permissions)?.label ?? customLabel;
}

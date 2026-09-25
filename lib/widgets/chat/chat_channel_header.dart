import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The open channel's name, and its topic when it has one, above its
/// messages, with its settings beside them (#2422).
///
/// The settings button opens a menu of the actions whose callbacks are set:
/// edit the name and topic, members, leave, and delete. With none set, as for
/// a reader in `general`, there is no button.
///
/// Keys: `chat_channel_settings` on the button; `chat_channel_edit`,
/// `chat_channel_members`, `chat_channel_leave` and `chat_channel_delete` on
/// the menu's items.
class ChatChannelHeader extends StatelessWidget {
  /// Creates the header for channel [name].
  const ChatChannelHeader({
    required this.name,
    this.topic = '',
    this.onEdit,
    this.onMembers,
    this.onDelete,
    this.onLeave,
    super.key,
  });

  /// The channel's name, shown after `#`.
  final String name;

  /// What the channel is for; empty shows nothing.
  final String topic;

  /// Opens the name and topic editor; null leaves it out of the menu.
  final VoidCallback? onEdit;

  /// Opens the members sheet; null leaves it out.
  final VoidCallback? onMembers;

  /// Asks to delete the channel; null leaves it out.
  final VoidCallback? onDelete;

  /// Asks to leave the channel; null leaves it out.
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final items = [
      if (onEdit case final onEdit?)
        MenuItemButton(
          key: const ValueKey('chat_channel_edit'),
          leadingIcon: const Icon(QuarkIcons.edit_outlined, size: 18),
          onPressed: onEdit,
          child: const Text('Edit name and topic'),
        ),
      if (onMembers case final onMembers?)
        MenuItemButton(
          key: const ValueKey('chat_channel_members'),
          leadingIcon: const Icon(QuarkIcons.group_outlined, size: 18),
          onPressed: onMembers,
          child: const Text('Members'),
        ),
      if (onLeave case final onLeave?)
        MenuItemButton(
          key: const ValueKey('chat_channel_leave'),
          leadingIcon: const Icon(QuarkIcons.logout, size: 18),
          onPressed: onLeave,
          child: const Text('Leave channel'),
        ),
      if (onDelete case final onDelete?)
        MenuItemButton(
          key: const ValueKey('chat_channel_delete'),
          leadingIcon: Icon(
            QuarkIcons.delete_outline,
            size: 18,
            color: tokens.error,
          ),
          onPressed: onDelete,
          child: Text('Delete channel', style: TextStyle(color: tokens.error)),
        ),
    ];
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '# $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (topic.isNotEmpty)
                Text(
                  topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.mutedForeground, fontSize: 12),
                ),
            ],
          ),
        ),
        if (items.isNotEmpty)
          MenuAnchor(
            menuChildren: items,
            builder: (context, menu, _) => QuarkBarIconButton(
              key: const ValueKey('chat_channel_settings'),
              icon: QuarkIcons.settings_outlined,
              tooltip: 'Channel settings',
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            ),
          ),
      ],
    );
  }
}

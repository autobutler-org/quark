import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The open channel's name, and its topic when it has one, above its
/// messages, with its settings beside them (#2422).
///
/// The settings button opens a menu of the actions whose callbacks are set:
/// edit the name and topic and members, then, under a divider so they are
/// hard to hit by mistake, leave and delete for everyone in the error color
/// (#2498). With none set, as for a reader in `general`, there is no button.
///
/// A private channel carries a lock whose tooltip says what that means
/// (#2501).
///
/// With [onSearch] set, a search button sits before the settings (#2429).
///
/// Keys: `chat_channel_search` on the search button; `chat_channel_settings`
/// on the settings button; `chat_channel_private` on the lock;
/// `chat_channel_edit`, `chat_channel_members`,
/// `chat_channel_menu_divider`, `chat_channel_leave` and
/// `chat_channel_delete` on the menu's items.
class ChatChannelHeader extends StatelessWidget {
  /// Creates the header for channel [name].
  const ChatChannelHeader({
    required this.name,
    this.topic = '',
    this.isPrivate = false,
    this.onSearch,
    this.onEdit,
    this.onMembers,
    this.onDelete,
    this.onLeave,
    super.key,
  });

  /// The channel's name, shown after `#`.
  final String name;

  /// What the lock beside a private channel's name says.
  static const privateTooltip =
      'Private: only its members can see it. Add people from Members.';

  /// What the channel is for; empty shows nothing.
  final String topic;

  /// Whether only the channel's members can see it, marked with a lock.
  final bool isPrivate;

  /// Opens or closes the search of this channel's messages; null leaves the
  /// button out.
  final VoidCallback? onSearch;

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
    final routine = [
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
    ];
    final danger = TextStyle(color: tokens.error);
    final destructive = [
      if (onLeave case final onLeave?)
        MenuItemButton(
          key: const ValueKey('chat_channel_leave'),
          leadingIcon: Icon(QuarkIcons.logout, size: 18, color: tokens.error),
          onPressed: onLeave,
          child: Text('Leave channel', style: danger),
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
          child: Text('Delete channel for everyone', style: danger),
        ),
    ];
    final items = [
      ...routine,
      if (routine.isNotEmpty && destructive.isNotEmpty)
        const Divider(key: ValueKey('chat_channel_menu_divider')),
      ...destructive,
    ];
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '# $name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (isPrivate) ...[
                    SizedBox(width: tokens.spacingXs),
                    Tooltip(
                      key: const ValueKey('chat_channel_private'),
                      message: privateTooltip,
                      child: Icon(
                        QuarkIcons.lock_outline,
                        size: 14,
                        color: tokens.mutedForeground,
                      ),
                    ),
                  ],
                ],
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
        if (onSearch case final onSearch?)
          QuarkBarIconButton(
            key: const ValueKey('chat_channel_search'),
            icon: QuarkIcons.search,
            tooltip: 'Search messages',
            onPressed: onSearch,
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

import 'package:material_ui/material_ui.dart';

import '../../theme/quark_tokens.dart';

/// The count of unread messages on a channel's row: a small filled pill
/// reading the number, or `99+` above 99, in the theme's primary color.
/// With [isMention] it counts the unread messages that mention the reader
/// instead, and reads the number after an `@`.
///
/// A screen reader and a hover get [labelFor] instead of the bare number.
/// It is decoration on the row, not a control, so it takes no callbacks.
///
/// A part of `ChatChannelTile`, which keys it `channel_unread_<id>` or
/// `channel_mention_<id>`, and tested through `QuarkChannelList`.
class ChatUnreadPill extends StatelessWidget {
  /// Creates the pill for [count] unread messages, or unread mentions with
  /// [isMention].
  const ChatUnreadPill({
    required this.count,
    this.isMention = false,
    super.key,
  });

  /// How many messages are unread. Above 99 the pill reads `99+`.
  final int count;

  /// Whether [count] is of the unread messages that mention the reader.
  final bool isMention;

  /// What the pill says aloud and on hover: `1 unread message`,
  /// `3 unread messages`, or `1 unread mention` with [isMention].
  static String labelFor(int count, {bool isMention = false}) {
    final noun = isMention ? 'mention' : 'message';
    return count == 1 ? '1 unread $noun' : '$count unread ${noun}s';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final label = labelFor(count, isMention: isMention);

    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.primary,
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingSm),
            child: Text(
              '${isMention ? '@' : ''}${count > 99 ? '99+' : count}',
              maxLines: 1,
              style: TextStyle(
                color: tokens.primaryForeground,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

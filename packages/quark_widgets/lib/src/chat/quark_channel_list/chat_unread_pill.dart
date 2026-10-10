import 'package:flutter/material.dart';

import '../../theme/quark_tokens.dart';

/// The count of unread messages on a channel's row: a small filled pill
/// reading the number, or `99+` above 99, in the theme's primary color.
///
/// A screen reader and a hover get [labelFor] instead of the bare number.
/// It is decoration on the row, not a control, so it takes no callbacks.
///
/// A part of `ChatChannelTile`, which keys it `channel_unread_<id>`, and
/// tested through `QuarkChannelList`.
class ChatUnreadPill extends StatelessWidget {
  /// Creates the pill for [count] unread messages.
  const ChatUnreadPill({required this.count, super.key});

  /// How many messages are unread. Above 99 the pill reads `99+`.
  final int count;

  /// What the pill says aloud and on hover: `1 unread message`,
  /// `3 unread messages`.
  static String labelFor(int count) =>
      count == 1 ? '1 unread message' : '$count unread messages';

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final label = labelFor(count);

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
              count > 99 ? '99+' : '$count',
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

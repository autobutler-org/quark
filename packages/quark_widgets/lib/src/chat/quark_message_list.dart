import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_avatar.dart';
import '../core/quark_loader.dart';
import '../models/chat_message_item.dart';
import '../models/chat_permission.dart';
import '../theme/quark_tokens.dart';
import 'quark_message_list/chat_day_separator.dart';
import 'quark_message_list/chat_load_older_row.dart';
import 'quark_message_list/chat_message_row.dart';
import 'quark_message_list/chat_system_line.dart';

/// A channel's messages, newest at the bottom, built lazily so a long history
/// costs only what is on screen.
///
/// [messages] is ordered **newest first**, the order a reversed list builds
/// in, so loading older messages appends to the end. Consecutive messages
/// from one author within [groupWindow] share one avatar and name, a rule
/// across the list marks each new day, and system lines, messages waiting for
/// their key, and deleted messages each draw their own way (see
/// [ChatMessageKind]).
///
/// Loading is the caller's: [isLoading], [error] and [hasMore] come in and
/// [onLoadOlder] goes out. With no messages, loading shows a spinner, an
/// error shows the caller's sentence with a retry that fires [onLoadOlder],
/// and otherwise the list says the channel
/// is empty. With messages, the same states show in a row at the top, and
/// [onLoadOlder] also fires when the list is scrolled within
/// [loadOlderExtent] of the top. It can fire more than once before the caller
/// sets [isLoading], so the caller ignores a request while one is out.
///
/// Nothing here animates: new messages appear at the bottom in place. A
/// caller that scrolls to the newest message with [controller] checks
/// reduced motion itself and jumps rather than animates when it is on.
///
/// A delete button sits on each text message the user may delete: their own,
/// which authorship allows, or anyone's when [permissions] holds
/// [ChatPermission.deleteMessages]. It fires [onDelete]; the caller asks for
/// confirmation if it wants one.
///
/// [permissions] without [ChatPermission.readMessages] is someone who manages
/// the channel without being in the conversation. They get [notMemberText]
/// in place of the list: no messages, no spinner and no waiting for a key,
/// because no key is coming.
///
/// Key prefixes: `message_<id>` on each message, `message_delete_<id>` on its
/// delete button, `message_list_load_older` on the load button,
/// `message_list_retry` on the retry button, and `message_list_not_member`
/// on the not-a-member pane.
///
/// ```dart
/// QuarkMessageList(
///   messages: controller.messages,
///   isLoading: controller.isLoadingOlder,
///   error: olderError,
///   hasMore: controller.hasOlder,
///   onLoadOlder: controller.loadOlder,
///   permissions: controller.selectedPermissions,
///   currentUserId: controller.userId,
///   onDelete: controller.deleteMessage,
///   avatarBuilder: (context, userId) => AppAvatar(userId: userId),
/// );
/// ```
class QuarkMessageList extends StatelessWidget {
  /// Creates the list of [messages], newest first.
  const QuarkMessageList({
    required this.messages,
    this.isLoading = false,
    this.error,
    this.hasMore = false,
    this.onLoadOlder,
    this.permissions,
    this.currentUserId,
    this.onDelete,
    this.avatarBuilder,
    this.controller,
    super.key,
  });

  /// How close together one author's messages have to be to share a header.
  static const Duration groupWindow = Duration(minutes: 5);

  /// How near the top, in pixels, scrolling asks for older messages.
  static const double loadOlderExtent = 400;

  /// The diameter of each group's avatar.
  static const double avatarSize = 32;

  /// The messages, newest first.
  final List<ChatMessageItem> messages;

  /// Whether messages are loading: the first page when [messages] is empty,
  /// older ones otherwise.
  final bool isLoading;

  /// A sentence saying why messages could not be loaded, composed by the
  /// caller.
  final String? error;

  /// Whether there are messages older than the oldest in [messages].
  final bool hasMore;

  /// Asks for the page of messages older than the oldest shown, or for the
  /// first page when [messages] is empty. Fires from the load button, the
  /// retry button, and scrolling near the top while [hasMore]. Null never
  /// asks, and shows no retry.
  final VoidCallback? onLoadOlder;

  /// What the signed-in account may do in the channel.
  /// [ChatPermission.deleteMessages] puts a delete button on everyone's
  /// messages, and a set without [ChatPermission.readMessages] shows
  /// [notMemberText] instead of the list. Null checks nothing and offers
  /// delete on the user's own messages only.
  final Set<ChatPermission>? permissions;

  /// The signed-in account's id, whose own messages always carry a delete
  /// button. Null matches no author.
  final String? currentUserId;

  /// Called with a message's id to delete it. Null leaves every delete
  /// button out.
  final ValueChanged<String>? onDelete;

  /// Builds the avatar for an author's id, [avatarSize] across. Null draws
  /// a [QuarkAvatar] with the author's initials.
  final Widget Function(BuildContext context, String userId)? avatarBuilder;

  /// The list's scroll controller, for a caller that jumps to the newest
  /// message. Offset zero is the bottom.
  final ScrollController? controller;

  /// Shown in place of the list to someone who manages the channel but can't
  /// read it.
  static const String notMemberText =
      'You are not a member of this conversation';

  /// Whether [newer] starts a new header group after [older], the message
  /// before it in time.
  static bool startsGroup(ChatMessageItem newer, ChatMessageItem? older) =>
      older == null ||
      !isSameDay(newer.sentAt, older.sentAt) ||
      newer.kind == ChatMessageKind.system ||
      older.kind == ChatMessageKind.system ||
      newer.authorId != older.authorId ||
      newer.sentAt.difference(older.sentAt) > groupWindow;

  /// Whether [a] and [b] fall on the same calendar day.
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final onLoadOlder = this.onLoadOlder;
    final avatarBuilder = this.avatarBuilder;
    final onDelete = this.onDelete;
    final permissions = this.permissions;
    final deletesAny =
        permissions?.contains(ChatPermission.deleteMessages) ?? false;

    if (permissions != null &&
        !permissions.contains(ChatPermission.readMessages)) {
      return const EmptyStateWidget(
        key: ValueKey('message_list_not_member'),
        icon: QuarkIcons.lock_outline,
        headline: notMemberText,
        subtext: 'You can manage it, but its messages are not shared with you.',
      );
    }

    if (messages.isEmpty) {
      if (isLoading) return const Center(child: QuarkLoader());
      if (error != null) {
        // The first page failed: the same error and retry as the top row.
        return Center(
          child: ChatLoadOlderRow(
            isLoading: false,
            hasMore: false,
            error: error,
            onLoadOlder: onLoadOlder,
          ),
        );
      }
      return const EmptyStateWidget(
        icon: QuarkIcons.forum_outlined,
        headline: 'No messages yet',
        subtext: 'Say hello.',
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (hasMore &&
            !isLoading &&
            error == null &&
            onLoadOlder != null &&
            notification.metrics.extentAfter < loadOlderExtent) {
          onLoadOlder();
        }
        return false;
      },
      child: ListView.builder(
        controller: controller,
        reverse: true,
        padding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
        itemCount: messages.length + 1,
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return ChatLoadOlderRow(
              isLoading: isLoading,
              hasMore: hasMore,
              error: error,
              onLoadOlder: onLoadOlder,
            );
          }
          final message = messages[index];
          final older = index + 1 < messages.length
              ? messages[index + 1]
              : null;
          final startsDay =
              older == null || !isSameDay(message.sentAt, older.sentAt);

          return Column(
            key: ValueKey('message_${message.id}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (startsDay) ChatDaySeparator(date: message.sentAt),
              if (message.kind == ChatMessageKind.system)
                ChatSystemLine(message: message)
              else
                ChatMessageRow(
                  message: message,
                  avatarSize: avatarSize,
                  onDelete:
                      onDelete == null ||
                          message.kind != ChatMessageKind.text ||
                          !(deletesAny || message.authorId == currentUserId)
                      ? null
                      : () => onDelete(message.id),
                  avatar: !startsGroup(message, older)
                      ? null
                      : avatarBuilder != null
                      ? SizedBox.square(
                          dimension: avatarSize,
                          child: avatarBuilder(context, message.authorId),
                        )
                      : QuarkAvatar(
                          id: message.authorId,
                          name: message.authorName,
                          size: avatarSize,
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}

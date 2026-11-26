import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../models/chat_message_item.dart';
import '../theme/quark_tokens.dart';
import 'quark_branch_list/branch_list_row.dart';

/// A channel's side conversations (#4351), one row per message that has
/// one, drawn as a `BranchListRow`: the message's first line, its author,
/// and "3 replies, last 2h ago", in bold while it has unread replies.
///
/// [branches] are drawn in the order given, which is the caller's, newest
/// last reply first. A row whose last reply came before [quietBefore] is
/// quiet: it goes under a "Quiet" heading at the bottom, folded away until
/// [isQuietExpanded]. Tapping the heading calls [onQuietExpandedChanged];
/// whether it is open is the caller's. Folding only hides a row here.
///
/// A message that is deleted or still waiting for its key reads "Original
/// message unavailable" in place of its line; its side conversation still
/// opens. Loading, the error and the empty list are explicit: [isLoading]
/// with no rows shows a loader, [error] shows in place of the rows, and no
/// rows says so. With [hasMore], a "Load more" button at the foot calls
/// [onLoadMore], or a loader stands there while [isLoading].
///
/// The list fills its parent and scrolls on its own, so it sits in a pane or
/// a sheet. Nothing animates.
///
/// Key prefixes: `branch_row_<messageId>` on each row, `branch_list_quiet`
/// on the Quiet heading, `branch_list_load_more` on the Load more button,
/// `branch_list_loading` on a loader, `branch_list_error` on the error and
/// `branch_list_empty` on the empty state.
///
/// ```dart
/// QuarkBranchList(
///   branches: controller.branchList,
///   quietBefore: DateTime.now().subtract(ChatConfig.quietBranchAfter),
///   isQuietExpanded: controller.isQuietExpanded,
///   onQuietExpandedChanged: controller.setQuietExpanded,
///   isLoading: controller.isLoadingBranchList,
///   hasMore: controller.hasMoreBranches,
///   onLoadMore: controller.loadMoreBranches,
///   onOpen: (id) => context.go(AppRoutes.chatBranch(channelId, id)),
/// );
/// ```
class QuarkBranchList extends StatelessWidget {
  /// Creates the list of [branches].
  const QuarkBranchList({
    required this.branches,
    required this.quietBefore,
    required this.onOpen,
    this.isQuietExpanded = false,
    this.onQuietExpandedChanged,
    this.isLoading = false,
    this.error,
    this.hasMore = false,
    this.onLoadMore,
    super.key,
  });

  /// The messages with a side conversation, each with its
  /// [ChatMessageItem.branch], in the order to show them.
  final List<ChatMessageItem> branches;

  /// A side conversation whose last reply came before this is quiet.
  final DateTime quietBefore;

  /// Called with a row's message id when it is tapped.
  final ValueChanged<String> onOpen;

  /// Whether the quiet rows are shown under their heading.
  final bool isQuietExpanded;

  /// Called with the heading's new state when it is tapped. Null leaves the
  /// heading inert.
  final ValueChanged<bool>? onQuietExpandedChanged;

  /// Whether a page is loading.
  final bool isLoading;

  /// A sentence saying why the list could not be loaded, composed by the
  /// caller. Shown in place of the rows.
  final String? error;

  /// Whether there are older side conversations to load.
  final bool hasMore;

  /// Loads the next page. Null leaves the Load more button out.
  final VoidCallback? onLoadMore;

  /// The heading over the quiet rows.
  static const String quietTitle = 'Quiet';

  /// Whether [message]'s side conversation is quiet at [quietBefore]: its
  /// last reply came before it.
  static bool isQuiet(ChatMessageItem message, DateTime quietBefore) =>
      message.branch?.lastReplyAt.isBefore(quietBefore) ?? true;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final onQuietExpandedChanged = this.onQuietExpandedChanged;
    final onLoadMore = this.onLoadMore;
    final now = DateTime.now();
    final active = [
      for (final m in branches)
        if (!isQuiet(m, quietBefore)) m,
    ];
    final quiet = [
      for (final m in branches)
        if (isQuiet(m, quietBefore)) m,
    ];
    const loader = Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: QuarkLoader(key: ValueKey('branch_list_loading'))),
    );

    BranchListRow row(ChatMessageItem message) => BranchListRow(
      key: ValueKey('branch_row_${message.id}'),
      message: message,
      now: now,
      onTap: () => onOpen(message.id),
    );

    return ListView(
      padding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
      children: [
        if (error != null)
          Padding(
            padding: EdgeInsets.all(tokens.spacingMd),
            child: Text(
              error,
              key: const ValueKey('branch_list_error'),
              style: TextStyle(color: tokens.error),
            ),
          )
        else if (branches.isEmpty && isLoading)
          loader
        else if (branches.isEmpty)
          const EmptyStateWidget(
            key: ValueKey('branch_list_empty'),
            icon: QuarkIcons.side_conversation,
            headline: 'No side conversations yet',
          )
        else ...[
          for (final m in active) row(m),
          if (quiet.isNotEmpty) ...[
            Divider(height: 1, color: tokens.border),
            ListTile(
              key: const ValueKey('branch_list_quiet'),
              title: Text(
                '$quietTitle (${quiet.length})',
                style: TextStyle(
                  color: tokens.secondaryForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Icon(
                isQuietExpanded
                    ? QuarkIcons.expand_less
                    : QuarkIcons.expand_more,
                color: tokens.mutedForeground,
              ),
              onTap: onQuietExpandedChanged == null
                  ? null
                  : () => onQuietExpandedChanged(!isQuietExpanded),
            ),
            if (isQuietExpanded)
              for (final m in quiet) row(m),
          ],
          if (hasMore && isLoading)
            loader
          else if (hasMore && onLoadMore != null)
            Center(
              child: TextButton(
                key: const ValueKey('branch_list_load_more'),
                onPressed: onLoadMore,
                child: const Text('Load more'),
              ),
            ),
        ],
      ],
    );
  }
}

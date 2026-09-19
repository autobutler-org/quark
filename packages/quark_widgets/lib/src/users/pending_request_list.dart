import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../models/user_account_item.dart';
import '../theme/quark_tokens.dart';
import 'pending_request_list/pending_request_row.dart';

/// Account requests waiting for an admin, one row each with approve and deny.
///
/// Loading, the error and the empty list are the caller's to decide, and each
/// renders on its own. The rows lay out as a column, so the list sits in a
/// page's own scroll view with the sections around it.
///
/// Key prefixes: `request_row_<username>` on each row, and
/// `request_approve_<username>` and `request_deny_<username>` on its buttons.
///
/// ```dart
/// PendingRequestList(
///   requests: controller.pending,
///   busyUsernames: controller.busyUsernames,
///   onApprove: approve,
///   onDeny: deny,
/// );
/// ```
class PendingRequestList extends StatelessWidget {
  /// Creates the list of [requests].
  const PendingRequestList({
    required this.requests,
    this.isLoading = false,
    this.error,
    this.busyUsernames = const {},
    this.onApprove,
    this.onDeny,
    super.key,
  });

  /// The requested accounts, in the order they are shown.
  final List<UserAccountItem> requests;

  /// Whether the requests are still loading. Shows a spinner in place of the
  /// rows.
  final bool isLoading;

  /// A sentence saying why the requests could not be loaded, composed by the
  /// caller. Shown in place of the rows.
  final String? error;

  /// Requests with an approve or deny in flight. Their rows show progress in
  /// place of the buttons.
  final Set<String> busyUsernames;

  /// Called with the username to approve. Null disables the button.
  final ValueChanged<String>? onApprove;

  /// Called with the username to deny. Null disables the button.
  final ValueChanged<String>? onDeny;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final onApprove = this.onApprove;
    final onDeny = this.onDeny;

    if (isLoading) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.spacingMd),
        child: Text(error, style: TextStyle(color: tokens.error)),
      );
    }
    if (requests.isEmpty) {
      return const EmptyStateWidget(
        icon: QuarkIcons.person_outline,
        headline: 'No requests waiting',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final request in requests)
          PendingRequestRow(
            username: request.username,
            isBusy: busyUsernames.contains(request.username),
            onApprove: onApprove == null
                ? null
                : () => onApprove(request.username),
            onDeny: onDeny == null ? null : () => onDeny(request.username),
          ),
      ],
    );
  }
}

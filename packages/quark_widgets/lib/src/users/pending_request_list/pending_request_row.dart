import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_loader.dart';
import '../../theme/quark_tokens.dart';

/// One request in a [PendingRequestList]: who asked, and approve and deny.
///
/// A part of [PendingRequestList], tested through it.
///
/// Key prefixes: `request_row_<username>`, `request_approve_<username>`, and
/// `request_deny_<username>`.
class PendingRequestRow extends StatelessWidget {
  /// Creates the row for the request from [username].
  const PendingRequestRow({
    required this.username,
    this.isBusy = false,
    this.onApprove,
    this.onDeny,
    super.key,
  });

  /// The requested username.
  final String username;

  /// Whether an approve or deny is in flight for this request.
  final bool isBusy;

  /// Approves the request. Null disables the button.
  final VoidCallback? onApprove;

  /// Denies the request. Null disables the button.
  final VoidCallback? onDeny;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return ListTile(
      key: ValueKey('request_row_$username'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(QuarkIcons.person_outline),
      title: Text(username, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        'Waiting for approval',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: tokens.mutedForeground),
      ),
      trailing: isBusy
          ? const QuarkLoader(size: 24)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  key: ValueKey('request_deny_$username'),
                  onPressed: onDeny,
                  child: const Text('Deny'),
                ),
                SizedBox(width: tokens.spacingXs),
                FilledButton(
                  key: ValueKey('request_approve_$username'),
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              ],
            ),
    );
  }
}

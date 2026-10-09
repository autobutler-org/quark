import 'package:flutter/material.dart';
import 'package:quark/models/account_request_decision.dart';
import 'package:quark/utils/relative_time.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One decision in a [RecentDecisionsList]: who asked, whether they were
/// approved or denied, which admin decided, and how long ago.
///
/// A part of `RecentDecisionsList`, tested through it. The caller keys it.
class RecentDecisionRow extends StatelessWidget {
  /// Creates the row for [decision].
  const RecentDecisionRow({required this.decision, super.key});

  /// The decision to show.
  final AccountRequestDecision decision;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final outcome = decision.approved ? 'Approved' : 'Denied';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        decision.approved ? QuarkIcons.check_circle_outline : QuarkIcons.close,
      ),
      title: Text(
        decision.username,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$outcome by ${decision.decidedBy} · '
        '${formatRelative(decision.decidedAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: tokens.mutedForeground),
      ),
    );
  }
}

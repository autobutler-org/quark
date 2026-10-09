import 'package:flutter/material.dart';
import 'package:quark/models/account_request_decision.dart';
import 'package:quark/widgets/users/recent_decisions/recent_decision_row.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The account requests admins approved or denied (#2730), one row each,
/// in the order given.
///
/// Loading, the error and the empty list are the caller's to decide, and each
/// renders on its own. The rows lay out as a column, so the list sits in a
/// page's own scroll view with the sections around it.
///
/// Key prefixes: `decision_row_<index>` on each row, counting from 0 at the
/// top.
///
/// ```dart
/// RecentDecisionsList(decisions: controller.decisions);
/// ```
class RecentDecisionsList extends StatelessWidget {
  /// Creates the list of [decisions].
  const RecentDecisionsList({
    required this.decisions,
    this.isLoading = false,
    this.error,
    super.key,
  });

  /// The decisions, in the order they are shown.
  final List<AccountRequestDecision> decisions;

  /// Whether the decisions are still loading. Shows a spinner in place of the
  /// rows.
  final bool isLoading;

  /// A sentence saying why the decisions could not be loaded, composed by the
  /// caller. Shown in place of the rows.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;

    if (isLoading) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: const Center(child: QuarkLoader()),
      );
    }
    if (error != null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.spacingMd),
        child: Text(error, style: TextStyle(color: tokens.error)),
      );
    }
    if (decisions.isEmpty) {
      return const EmptyStateWidget(
        icon: QuarkIcons.access_time_outlined,
        headline: 'No decisions yet',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, decision) in decisions.indexed)
          RecentDecisionRow(
            key: ValueKey('decision_row_$index'),
            decision: decision,
          ),
      ],
    );
  }
}

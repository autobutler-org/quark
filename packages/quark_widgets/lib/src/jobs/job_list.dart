import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../models/job_item.dart';
import '../theme/quark_tokens.dart';
import 'job_list/job_row.dart';

/// Long-running jobs, newest first, each with its status, progress, and the
/// Cancel or Retry action its [JobItem] offers.
///
/// Loading and error are inputs. A spinner or the [error] text replaces the
/// list only while there are no [items]; with items on screen the error sits
/// above them, so a failed refresh never hides what was already known.
///
/// Key prefixes: `job_row_<id>` on each row, `job_cancel_<id>` and
/// `job_retry_<id>` on its actions.
///
/// ```dart
/// JobList(
///   items: controller.items,
///   isLoading: controller.isLoading,
///   error: controller.error,
///   onCancel: cancel,
///   onRetry: retry,
/// );
/// ```
class JobList extends StatelessWidget {
  /// Creates a list of [items].
  const JobList({
    required this.items,
    this.isLoading = false,
    this.error,
    this.onCancel,
    this.onRetry,
    super.key,
  });

  /// The jobs to show, in order.
  final List<JobItem> items;

  /// Whether jobs are being fetched. Shows a spinner while [items] is empty.
  final bool isLoading;

  /// A sentence the caller composed about a failed fetch, or null.
  final String? error;

  /// Called with the id of the job whose Cancel was tapped.
  final ValueChanged<int>? onCancel;

  /// Called with the id of the job whose Retry was tapped.
  final ValueChanged<int>? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final errorText = error == null
        ? null
        : Padding(
            padding: EdgeInsets.all(tokens.spacingMd),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.error),
            ),
          );

    if (items.isEmpty) {
      if (isLoading) return const Center(child: QuarkLoader());
      if (errorText != null) return Center(child: errorText);
      return const EmptyStateWidget(
        icon: QuarkIcons.pending_actions_outlined,
        headline: 'No jobs yet',
        // Names the thing a household would recognize rather than the
        // category it belongs to: "conversions" is a word for someone who
        // already knows this page exists (#2038).
        subtext:
            'Work that takes a while — converting a video, say — shows up '
            'here while your Quark gets on with it.',
      );
    }

    return ListView(
      children: [
        ?errorText,
        for (final item in items)
          JobRow(item: item, onCancel: onCancel, onRetry: onRetry),
      ],
    );
  }
}

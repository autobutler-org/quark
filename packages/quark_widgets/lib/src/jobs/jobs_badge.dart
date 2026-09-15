import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// A top-bar button counting the jobs running now. Renders nothing while
/// [runningCount] is zero, so it only takes space when there is news.
///
/// Key prefixes: `jobs_badge` on the button.
///
/// ```dart
/// JobsBadge(
///   runningCount: controller.runningCount,
///   onTap: () => context.go(AppRoutes.jobs),
/// );
/// ```
class JobsBadge extends StatelessWidget {
  /// Creates a badge counting [runningCount] jobs.
  const JobsBadge({required this.runningCount, required this.onTap, super.key});

  /// How many jobs are running. Zero hides the badge.
  final int runningCount;

  /// Called when the badge is tapped, usually to open the jobs page.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (runningCount <= 0) return const SizedBox.shrink();
    final tokens = QuarkTokens.of(context);
    return IconButton(
      key: const ValueKey('jobs_badge'),
      tooltip: runningCount == 1
          ? '1 job running'
          : '$runningCount jobs running',
      onPressed: onTap,
      icon: Badge(
        label: Text('$runningCount'),
        backgroundColor: tokens.primary,
        textColor: tokens.primaryForeground,
        child: const Icon(QuarkIcons.pending_actions_outlined),
      ),
    );
  }
}

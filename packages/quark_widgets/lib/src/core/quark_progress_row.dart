import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// The one progress row: a name with its actions, an optional muted line, a
/// status line, and a progress bar while [progress] is set.
///
/// The row owns the layout: the `titleSmall` name wraps to two lines beside
/// the [actions], the `bodySmall` status line draws its digits at equal
/// width so a ticking clock or byte count does not jitter, and the bar sits
/// under it on the [QuarkTokens.border] track. The caller owns the words: the
/// name, how bytes, rates and elapsed time read, and which actions exist.
/// `JobRow` and `UploadRow` are built on it.
///
/// Key prefixes: none of its own. The caller's `key` sits on the row, and
/// each action carries its own.
///
/// ```dart
/// QuarkProgressRow(
///   key: const ValueKey('job_row_7'),
///   title: 'Convert vacation.mov',
///   status: 'Running · 40% · 0:12',
///   progress: 0.4,
///   actions: [
///     TextButton(
///       key: const ValueKey('job_cancel_7'),
///       onPressed: () => cancel(7),
///       child: const Text('Cancel'),
///     ),
///   ],
/// );
/// ```
class QuarkProgressRow extends StatelessWidget {
  /// Creates a row named [title] reading [status].
  const QuarkProgressRow({
    required this.title,
    required this.status,
    this.statusColor,
    this.subtitle,
    this.progress,
    this.actions = const [],
    super.key,
  });

  /// The name, such as a file name. Wraps to two lines, then trails off.
  final String title;

  /// The status line, such as `Running · 40% · 0:12`.
  final String status;

  /// The status line's color. Null for [QuarkTokens.mutedForeground].
  final Color? statusColor;

  /// A muted one-line note between the name and the status, such as a
  /// destination folder. Null for none.
  final String? subtitle;

  /// How far along, from 0 to 1, clamped. Null hides the bar.
  final double? progress;

  /// The buttons after the name, such as Cancel or Retry. Each one carries
  /// its own key and callback.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final subtitle = this.subtitle;
    final progress = this.progress;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacingMd,
        vertical: tokens.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              ...actions,
            ],
          ),
          if (subtitle != null)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.mutedForeground,
              ),
            ),
          Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: statusColor ?? tokens.mutedForeground,
              // Percentages, clocks and byte counts change while the row is
              // on screen; equal-width digits keep the line from jittering.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (progress != null)
            Padding(
              padding: EdgeInsets.only(top: tokens.spacingXs),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1).toDouble(),
                color: tokens.primary,
                backgroundColor: tokens.border,
              ),
            ),
        ],
      ),
    );
  }
}

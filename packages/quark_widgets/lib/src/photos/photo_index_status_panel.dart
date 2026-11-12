import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../models/photo_index_failure_item.dart';
import '../theme/quark_tokens.dart';
import 'photo_index_status_panel/photo_index_failure_row.dart';

/// The photo library index's state, shown above results that depend on it,
/// such as duplicates (#3556), so "no duplicates found" is never mistaken for
/// "none exist" while the library is still being read.
///
/// While a pass is running, paused, or has not covered the library, a
/// warning-tinted panel says results may be incomplete, with how many photos
/// can be compared and how many dates have been read. A complete index says
/// so, with when its last pass finished.
///
/// With [onPause] and [onResume] it offers to pause a running pass or resume
/// a paused one; leave them null where the viewer may not. When [failed] is
/// above zero, a toggle shows or hides [failures], each with its reason. The
/// caller holds whether they are shown ([showFailures]) and words each
/// reason. [isLoading] shows a loader in place of the counts, and [error] a
/// message the caller wrote; either replaces the rest.
///
/// Key prefixes: `photo_index_status` on the panel, `photo_index_pause` and
/// `photo_index_resume` on the control, `photo_index_failures_toggle` on the
/// toggle, and `photo_index_failure_<id>` on each failure.
///
/// ```dart
/// PhotoIndexStatusPanel(
///   total: status.total,
///   hashed: status.hashed,
///   datesRead: status.datesRead,
///   failed: status.failed,
///   isRunning: status.running,
///   isPaused: status.paused,
///   failures: controller.failures,
///   showFailures: controller.showFailures,
///   onToggleFailures: controller.toggleFailures,
///   onPause: controller.pause,
///   onResume: controller.resume,
/// );
/// ```
class PhotoIndexStatusPanel extends StatelessWidget {
  /// Creates the panel.
  const PhotoIndexStatusPanel({
    this.total = 0,
    this.hashed = 0,
    this.datesRead = 0,
    this.failed = 0,
    this.isRunning = false,
    this.isPaused = false,
    this.lastRunAt,
    this.failures = const [],
    this.showFailures = false,
    this.onToggleFailures,
    this.onPause,
    this.onResume,
    this.isChanging = false,
    this.isLoading = false,
    this.error,
    super.key,
  });

  /// The photos in the library.
  final int total;

  /// The photos that can be compared for duplicates.
  final int hashed;

  /// The photos whose capture date has been read.
  final int datesRead;

  /// The photos that could not be read, listed or not.
  final int failed;

  /// Whether a pass is under way, paused or not.
  final bool isRunning;

  /// Whether the pass is paused.
  final bool isPaused;

  /// When a pass last finished, or null if none has.
  final DateTime? lastRunAt;

  /// The failures to list, possibly fewer than [failed].
  final List<PhotoIndexFailureItem> failures;

  /// Whether [failures] are shown.
  final bool showFailures;

  /// Called by the failure toggle. Null hides the toggle.
  final VoidCallback? onToggleFailures;

  /// Called by Pause on a running pass. Null hides it.
  final VoidCallback? onPause;

  /// Called by Resume on a paused pass. Null hides it.
  final VoidCallback? onResume;

  /// Whether a pause or resume is in flight, which disables the control.
  final bool isChanging;

  /// Whether the status is loading.
  final bool isLoading;

  /// A user-facing message for a status that could not be loaded, or null.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    final incomplete = isRunning || isPaused || hashed + failed < total;
    final accent = error != null || incomplete
        ? tokens.warning
        : tokens.success;
    final title = isPaused
        ? 'Indexing paused, so results may be incomplete'
        : isRunning
        ? 'Still indexing, so results may be incomplete'
        : incomplete
        ? 'Not every photo is indexed, so results may be incomplete'
        : 'All $total photos indexed';
    final lastRunAt = this.lastRunAt;
    final localizations = MaterialLocalizations.of(context);
    final detail = [
      if (incomplete) '$hashed of $total photos checked for duplicates',
      if (incomplete) '$datesRead dates read',
      if (!incomplete && lastRunAt != null)
        'Last finished ${localizations.formatMediumDate(lastRunAt)}, '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(lastRunAt))}',
    ].join(' · ');
    final onPause = isRunning && !isPaused ? this.onPause : null;
    final onResume = isPaused ? this.onResume : null;
    final onToggleFailures = failed > 0 ? this.onToggleFailures : null;

    return Container(
      key: const ValueKey('photo_index_status'),
      padding: EdgeInsets.all(tokens.spacingMd),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.08), tokens.card),
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Semantics(
        liveRegion: true,
        child: isLoading
            ? Row(
                spacing: tokens.spacingSm,
                children: [
                  const QuarkLoader(size: 20),
                  Expanded(
                    child: Text(
                      'Checking the photo index…',
                      style: TextStyle(color: tokens.mutedForeground),
                    ),
                  ),
                ],
              )
            : error != null
            ? Row(
                spacing: tokens.spacingSm,
                children: [
                  Icon(QuarkIcons.error_outline, size: 18, color: accent),
                  Expanded(
                    child: Text(
                      error,
                      style: TextStyle(color: tokens.foreground),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: tokens.spacingSm,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: tokens.spacingSm,
                    children: [
                      Icon(
                        incomplete
                            ? QuarkIcons.info_outline
                            : QuarkIcons.check_circle_outline,
                        size: 18,
                        color: accent,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: tokens.foreground,
                              ),
                            ),
                            if (detail.isNotEmpty)
                              Text(
                                detail,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tokens.mutedForeground,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (onPause != null ||
                      onResume != null ||
                      onToggleFailures != null)
                    Wrap(
                      spacing: tokens.spacingSm,
                      runSpacing: tokens.spacingXs,
                      children: [
                        if (onPause != null)
                          OutlinedButton.icon(
                            key: const ValueKey('photo_index_pause'),
                            onPressed: isChanging ? null : onPause,
                            icon: const Icon(QuarkIcons.pause, size: 18),
                            label: const Text('Pause indexing'),
                          ),
                        if (onResume != null)
                          OutlinedButton.icon(
                            key: const ValueKey('photo_index_resume'),
                            onPressed: isChanging ? null : onResume,
                            icon: const Icon(QuarkIcons.play_arrow, size: 18),
                            label: const Text('Resume indexing'),
                          ),
                        if (onToggleFailures != null)
                          TextButton.icon(
                            key: const ValueKey('photo_index_failures_toggle'),
                            onPressed: onToggleFailures,
                            icon: Icon(
                              showFailures
                                  ? QuarkIcons.expand_less
                                  : QuarkIcons.expand_more,
                              size: 18,
                            ),
                            label: Text(
                              failed == 1
                                  ? "1 photo couldn't be read"
                                  : "$failed photos couldn't be read",
                            ),
                          ),
                      ],
                    ),
                  if (showFailures && failures.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: failures.length,
                        itemBuilder: (context, index) =>
                            PhotoIndexFailureRow(failure: failures[index]),
                      ),
                    ),
                  if (showFailures && failures.length < failed)
                    Text(
                      'Showing the first ${failures.length} of $failed.',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.mutedForeground,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

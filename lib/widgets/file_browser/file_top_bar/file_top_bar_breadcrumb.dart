import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Smart breadcrumb (all viewports).
///
/// Renders a pill container with the home icon pinned left and path segments
/// to the right. Two truncation cases are handled:
///
///  Case 1 — Long segment name: the name is middle-truncated to fit within a
///            per-segment pixel cap (MyLong…Name), preserving both ends.
///
///  Case 2 — Too many segments: leading (ancestor) segments are dropped and a
///            "⋯" indicator is prepended until the remainder fits the available
///            width. The home icon is always visible.
///
/// Segments outside [rootPath] are shown but not offered: a member's reach
/// starts at their own home, and the `users` folder on the way to it is a
/// waypoint they cannot use (#2139).
class FileTopBarBreadcrumb extends StatelessWidget {
  const FileTopBarBreadcrumb({
    required this.currentPath,
    required this.rootPath,
    required this.navEnabled,
    required this.hiddenCrumbsController,
    required this.onGoHome,
    this.onPathSelected,
    super.key,
  });

  final String currentPath;

  /// The lowest folder the caller can open — empty for the real root.
  final String rootPath;
  final bool navEnabled;

  /// Owned by the top bar so the popup of hidden ancestors survives the
  /// breadcrumb being rebuilt as the path changes.
  final MenuController hiddenCrumbsController;
  final VoidCallback onGoHome;
  final ValueChanged<String>? onPathSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final trimmed = currentPath.startsWith('/')
        ? currentPath.substring(1)
        : currentPath;
    final segments = trimmed.isEmpty ? <String>[] : trimmed.split('/');
    // Home opens [rootPath], so once there it would go nowhere: it stops
    // looking and behaving like a button, as the up button does (#2010).
    final canGoHome =
        navEnabled && normalizePath(currentPath) != normalizePath(rootPath);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(QuarkColors.radiusLg),
      ),
      // LayoutBuilder inside the Container so constraints.maxWidth already
      // reflects the width after the Container's padding is subtracted.
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Home icon — always visible, never truncated.
              MouseRegion(
                cursor: canGoHome
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: InkWell(
                  key: const ValueKey('file_top_bar_home'),
                  onTap: canGoHome ? onGoHome : null,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      QuarkIcons.home_rounded,
                      size: 16,
                      color: canGoHome
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
              if (segments.isNotEmpty) ...[
                const SizedBox(width: 2),
                ..._buildSmartCrumbs(context, segments, constraints.maxWidth),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Whether a crumb pointing at [target] may be tapped.
  bool _canOpen(String target) =>
      navEnabled && onPathSelected != null && isWithin(rootPath, target);

  /// Determines which segments to display given [availableWidth] (the inner
  /// width of the breadcrumb container after its padding is removed).
  ///
  /// Works by accumulating segment slots from the rightmost (current directory)
  /// towards the root. Stops as soon as adding the next segment would overflow,
  /// prepending a "⋯" indicator for any hidden ancestors.
  List<Widget> _buildSmartCrumbs(
    BuildContext context,
    List<String> segments,
    double availableWidth,
  ) {
    if (segments.isEmpty) return [];

    final colorScheme = Theme.of(context).colorScheme;

    // Space occupied by the home icon + small gap before the first crumb.
    const homeIconPx = 20.0; // Icon(16) + Padding(all(2)) = 16 + 4
    const homeGapPx = 2.0;
    // Each separator (chevron icon + horizontal padding).
    const separatorPx = 22.0; // Icon(14) + Padding(horizontal(4)) = 14 + 8
    // The "⋯" ellipsis prefix when ancestors are hidden (same visual budget).
    const ellipsisPx = 22.0;
    // Hard cap on a single segment's rendered text width.
    const maxSegmentPx = 140.0;
    // Text style used for segment labels.
    const segStyle = TextStyle(fontSize: 13);

    final budget = availableWidth - homeIconPx - homeGapPx;

    // Measure each segment, capped at maxSegmentPx.
    final segWidths = segments.map((s) {
      return math.min(_measureText(s, segStyle), maxSegmentPx);
    }).toList();

    // Slot cost for a segment = separator + text + small horizontal padding.
    List<double> slotCosts = segWidths.map((w) => separatorPx + w + 4).toList();

    // Greedily add segments from right to left until the budget is exhausted.
    double accumulated = 0;
    int visibleFrom = segments.length; // exclusive index; will shrink left

    for (int i = segments.length - 1; i >= 0; i--) {
      // If there are still ancestors to the left of i, we may need to show "⋯".
      final ellipsisNeeded = i > 0 ? ellipsisPx : 0.0;
      if (accumulated + slotCosts[i] + ellipsisNeeded <= budget) {
        accumulated += slotCosts[i];
        visibleFrom = i;
      } else {
        break;
      }
    }

    // Always show at least the current (last) directory even if it overflows.
    if (visibleFrom == segments.length) visibleFrom = segments.length - 1;

    final hasHidden = visibleFrom > 0;
    final result = <Widget>[];

    if (hasHidden) {
      // Build menu items for each hidden ancestor segment.
      final hiddenSegments = segments.sublist(0, visibleFrom);
      final menuItems = hiddenSegments.asMap().entries.map((entry) {
        final idx = entry.key;
        final name = entry.value;
        final targetPath = '/${segments.take(idx + 1).join('/')}';
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            idx == 0 ? QuarkIcons.home_rounded : QuarkIcons.folder_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          title: Text(name, style: const TextStyle(fontSize: 14)),
          onTap: !_canOpen(targetPath)
              ? null
              : () {
                  hiddenCrumbsController.close();
                  onPathSelected!(targetPath);
                },
        );
      }).toList();

      result.add(
        MenuAnchor(
          controller: hiddenCrumbsController,
          style: MenuStyle(
            minimumSize: const WidgetStatePropertyAll(Size(200, 0)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(QuarkColors.radiusLg),
              ),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          menuChildren: menuItems,
          child: MouseRegion(
            cursor: navEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: InkWell(
              onTap: !navEnabled
                  ? null
                  : () {
                      if (hiddenCrumbsController.isOpen) {
                        hiddenCrumbsController.close();
                      } else {
                        hiddenCrumbsController.open();
                      }
                    },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Icon(
                  QuarkIcons.more_horiz_rounded,
                  size: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ),
      );
    }

    for (int i = visibleFrom; i < segments.length; i++) {
      // Chevron separator before each segment.
      result.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            QuarkIcons.chevron_right_rounded,
            size: 14,
            color: colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );

      final isLast = i == segments.length - 1;
      final targetPath = '/${segments.take(i + 1).join('/')}';
      // Middle-truncate the label if it exceeds the per-segment pixel cap.
      final label = _middleTruncate(segments[i], maxSegmentPx, segStyle);

      final tappable = !isLast && _canOpen(targetPath);

      result.add(
        MouseRegion(
          cursor: tappable
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: InkWell(
            onTap: tappable ? () => onPathSelected!(targetPath) : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: tappable ? colorScheme.primary : colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
        ),
      );
    }

    return result;
  }

  /// Returns the pixel width of [text] rendered with [style].
  static double _measureText(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    return painter.width;
  }

  /// Middle-truncates [text] so that its rendered width fits within [maxPx].
  ///
  /// Keeps [head] characters from the front and [tail] characters from the
  /// back, joined by the Unicode ellipsis "…". Uses binary search to find
  /// the maximum number of kept characters that still fits.
  static String _middleTruncate(String text, double maxPx, TextStyle style) {
    if (text.isEmpty || _measureText(text, style) <= maxPx) return text;

    var lo = 2; // minimum: 1 head char + ellipsis + 1 tail char
    var hi = text.length - 1;

    while (lo < hi) {
      final total = (lo + hi + 1) ~/ 2;
      final head = (total + 1) ~/ 2;
      final tail = total - head;
      final candidate =
          '${text.substring(0, head)}…${text.substring(text.length - tail)}';
      if (_measureText(candidate, style) <= maxPx) {
        lo = total;
      } else {
        hi = total - 1;
      }
    }

    final head = (lo + 1) ~/ 2;
    final tail = lo - head;
    if (tail <= 0) return '${text[0]}…';
    return '${text.substring(0, head)}…${text.substring(text.length - tail)}';
  }
}

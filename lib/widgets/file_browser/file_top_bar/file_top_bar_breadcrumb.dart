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
///
/// Home, the "⋯" button and every ancestor are labeled 48dp targets, which
/// overhang the pill: the pill keeps a bar button's height, and the targets
/// reach [QuarkBarIconButton.tapTargetMargin] above and below it (#2603,
/// #2605).
///
/// Probe keys: `file_top_bar_home`, `file_top_bar_hidden_crumbs`,
/// `file_top_bar_crumb_<index>` counting from zero at the shallowest, and
/// `file_top_bar_pill` for the pill itself.
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
    final tokens = QuarkTokens.of(context);

    final trimmed = currentPath.startsWith('/')
        ? currentPath.substring(1)
        : currentPath;
    final segments = trimmed.isEmpty ? <String>[] : trimmed.split('/');
    // Home opens [rootPath], so once there it would go nowhere: it stops
    // looking and behaving like a button, as the up button does (#2010).
    final canGoHome =
        navEnabled && normalizePath(currentPath) != normalizePath(rootPath);

    return SizedBox(
      height: kMinInteractiveDimension,
      child: Stack(
        children: [
          Positioned.fill(
            top: QuarkBarIconButton.tapTargetMargin,
            bottom: QuarkBarIconButton.tapTargetMargin,
            child: DecoratedBox(
              key: const ValueKey('file_top_bar_pill'),
              decoration: BoxDecoration(
                color: tokens.input,
                border: Border.all(color: tokens.border),
                borderRadius: BorderRadius.circular(tokens.radiusLg),
              ),
            ),
          ),
          // Home's target supplies the left inset, so only a trailing crumb
          // needs padding after it. LayoutBuilder sits inside it so
          // constraints.maxWidth already has the padding subtracted.
          Padding(
            padding: EdgeInsets.only(right: segments.isEmpty ? 0 : 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Home icon — always visible, never truncated.
                    Semantics(
                      container: true,
                      button: canGoHome,
                      child: Tooltip(
                        message: canGoHome
                            ? 'Go to the top folder'
                            : 'You are in the top folder',
                        child: MouseRegion(
                          cursor: canGoHome
                              ? SystemMouseCursors.click
                              : SystemMouseCursors.basic,
                          child: GestureDetector(
                            key: const ValueKey('file_top_bar_home'),
                            behavior: HitTestBehavior.opaque,
                            onTap: canGoHome ? onGoHome : null,
                            child: SizedBox.square(
                              dimension: kMinInteractiveDimension,
                              child: Icon(
                                QuarkIcons.home_rounded,
                                size: 16,
                                color: canGoHome
                                    ? colorScheme.onSurfaceVariant
                                    : colorScheme.onSurface.withValues(
                                        alpha: 0.4,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ..._buildSmartCrumbs(
                      context,
                      segments,
                      constraints.maxWidth,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
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

    // Space occupied by the home target.
    const homeIconPx = kMinInteractiveDimension;
    // Each separator (chevron icon + horizontal padding).
    const separatorPx = 22.0; // Icon(14) + Padding(horizontal(4)) = 14 + 8
    // The "⋯" target prefixed when ancestors are hidden.
    const ellipsisPx = kMinInteractiveDimension;
    // Hard cap on a single segment's rendered text width.
    const maxSegmentPx = 140.0;
    // Text style used for segment labels.
    const segStyle = TextStyle(fontSize: 13);

    final budget = availableWidth - homeIconPx;

    // Measure each segment, capped at maxSegmentPx.
    final segWidths = segments.map((s) {
      return math.min(_measureText(s, segStyle), maxSegmentPx);
    }).toList();

    // Slot cost for a segment = separator + text and its small horizontal
    // padding, or the 48dp minimum target if that is wider.
    List<double> slotCosts = segWidths
        .map((w) => separatorPx + math.max(w + 4, kMinInteractiveDimension))
        .toList();

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
          child: Semantics(
            container: true,
            button: navEnabled,
            child: Tooltip(
              message: 'Show hidden folders',
              child: MouseRegion(
                cursor: navEnabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: GestureDetector(
                  key: const ValueKey('file_top_bar_hidden_crumbs'),
                  behavior: HitTestBehavior.opaque,
                  onTap: !navEnabled
                      ? null
                      : () {
                          if (hiddenCrumbsController.isOpen) {
                            hiddenCrumbsController.close();
                          } else {
                            hiddenCrumbsController.open();
                          }
                        },
                  child: SizedBox.square(
                    dimension: kMinInteractiveDimension,
                    child: Icon(
                      QuarkIcons.more_horiz_rounded,
                      size: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
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
        Semantics(
          container: true,
          button: tappable,
          child: MouseRegion(
            cursor: tappable
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              key: ValueKey('file_top_bar_crumb_$i'),
              behavior: HitTestBehavior.opaque,
              onTap: tappable ? () => onPathSelected!(targetPath) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: kMinInteractiveDimension,
                  minHeight: kMinInteractiveDimension,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: tappable
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                ),
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

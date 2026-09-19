import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// The path trail above a file listing: an up button, a home glyph, and one
/// tappable segment per ancestor directory.
///
/// The last segment is the current directory and is not tappable, since
/// tapping it would go nowhere. The trail scrolls horizontally rather than
/// wrapping, so a deep path never grows the bar's height on a narrow screen.
/// It renders nothing in search mode, where there is no path to show.
///
/// Key prefixes: `breadcrumb_up`, `breadcrumb_home`, and
/// `breadcrumb_segment_<index>` counting from zero at the shallowest.
///
/// ```dart
/// FileBreadcrumbBar(
///   currentPath: '/photos/2024',
///   isSearchMode: false,
///   onGoHome: () => controller.open('/'),
///   onGoUp: controller.goUp,
///   onPathSelected: controller.open,
/// );
/// ```
class FileBreadcrumbBar extends StatelessWidget {
  /// Creates a breadcrumb trail for [currentPath].
  const FileBreadcrumbBar({
    required this.currentPath,
    required this.onGoHome,
    required this.onGoUp,
    required this.onPathSelected,
    required this.isSearchMode,
    super.key,
  });

  /// The absolute path being shown, leading slash included. The empty string
  /// is the root, which disables the up button.
  final String currentPath;

  /// Navigates to the root.
  final VoidCallback onGoHome;

  /// Navigates to the parent directory. Not called at the root.
  final VoidCallback onGoUp;

  /// Called with the absolute path of the ancestor segment that was tapped.
  final ValueChanged<String> onPathSelected;

  /// Whether the listing is showing search results, which hides the trail.
  final bool isSearchMode;

  @override
  Widget build(BuildContext context) {
    if (isSearchMode) {
      return const SizedBox.shrink();
    }
    final tokens = QuarkTokens.of(context);
    final atRoot = currentPath.isEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacingMd,
        0,
        tokens.spacingMd,
        tokens.spacingSm,
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('breadcrumb_up'),
            onPressed: atRoot ? null : onGoUp,
            icon: const Icon(QuarkIcons.chevron_left_rounded),
            tooltip: 'Up one level',
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // At the top folder this is where you already are, so it
                  // stops looking and behaving like a button — it used to be
                  // primary-colored and tappable and answer a click with
                  // nothing at all (#2010). The up button beside it has
                  // always gone quiet here for the same reason.
                  Tooltip(
                    message: atRoot
                        ? 'You are in the top folder'
                        : 'Go to the top folder',
                    child: MouseRegion(
                      cursor: atRoot
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: GestureDetector(
                        key: const ValueKey('breadcrumb_home'),
                        onTap: atRoot ? null : onGoHome,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.spacingXs,
                          ),
                          child: Icon(
                            QuarkIcons.home_rounded,
                            size: 20,
                            color: atRoot
                                ? Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withValues(alpha: 0.4)
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ..._buildBreadcrumbs(context, tokens),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBreadcrumbs(BuildContext context, QuarkTokens tokens) {
    final style = Theme.of(context).textTheme.titleMedium;
    if (currentPath.isEmpty) {
      return [Text('/', style: style)];
    }

    final segments = currentPath.substring(1).split('/');
    final children = <Widget>[
      Padding(
        padding: EdgeInsets.only(right: tokens.spacingXs),
        child: Text('/', style: style),
      ),
    ];

    for (var index = 0; index < segments.length; index++) {
      if (index > 0) {
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingXs),
            child: Text('/', style: style),
          ),
        );
      }

      final segment = segments[index];
      final isLast = index == segments.length - 1;

      if (isLast) {
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingXs),
            child: Text(segment, style: style),
          ),
        );
        continue;
      }

      final targetPath = '/${segments.take(index + 1).join('/')}';
      children.add(
        GestureDetector(
          key: ValueKey('breadcrumb_segment_$index'),
          onTap: () => onPathSelected(targetPath),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingXs),
            child: Text(
              segment,
              style: style?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      );
    }

    return children;
  }
}

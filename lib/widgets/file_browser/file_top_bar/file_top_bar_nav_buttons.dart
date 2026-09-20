import 'package:flutter/material.dart';
import 'package:quark/widgets/file_browser/file_top_bar/top_bar_icon_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Back, up and refresh. Back and up both go up one level: the browser has no
/// history of its own, and the arrow the user reaches for should not depend on
/// which one they picked.
///
/// Both stop at [rootPath], the lowest folder the caller can open, so a member
/// pressing up in their own files is not walked into the `users` folder they
/// have no use for (#2139).
class FileTopBarNavButtons extends StatelessWidget {
  const FileTopBarNavButtons({
    required this.navEnabled,
    required this.currentPath,
    required this.rootPath,
    required this.isRefreshing,
    required this.onGoUp,
    required this.onRefresh,
    super.key,
  });

  final bool navEnabled;
  final String currentPath;

  /// The lowest folder the caller can open — empty for the real root.
  final String rootPath;
  final bool isRefreshing;
  final VoidCallback onGoUp;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final canGoUp =
        navEnabled && currentPath.isNotEmpty && currentPath != rootPath;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TopBarIconButton(
          icon: QuarkIcons.arrow_back_rounded,
          onTap: canGoUp ? onGoUp : null,
          tooltip: 'Back',
        ),
        const SizedBox(width: 4),
        TopBarIconButton(
          icon: QuarkIcons.arrow_upward_rounded,
          onTap: canGoUp ? onGoUp : null,
          tooltip: 'Up one level',
        ),
        const SizedBox(width: 4),
        RefreshIconButton(
          isRefreshing: isRefreshing,
          onPressed: onRefresh,
          tooltip: 'Refresh',
        ),
      ],
    );
  }
}

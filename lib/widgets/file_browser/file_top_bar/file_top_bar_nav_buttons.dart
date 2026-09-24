import 'package:flutter/material.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Up one level, drawn as a back arrow because that is the arrow users read
/// as "leave this folder". There is no separate Back: folder navigation
/// replaces the route rather than stacking it, so Back could only repeat up
/// (#2314). Web keeps the browser's own Back, which walks the visited-folder
/// URLs. The tooltip names the folder it lands in — "Back to docs", or
/// "Back to Files" at the top — so it does not read as history either. A
/// disabled arrow has nowhere to go, so it has no tooltip.
///
/// Up stops at [rootPath], the lowest folder the caller can open, so a member
/// pressing up in their own files is not walked into the `users` folder they
/// have no use for (#2139).
///
/// Probe keys: `file_top_bar_up`.
class FileTopBarNavButtons extends StatelessWidget {
  const FileTopBarNavButtons({
    required this.navEnabled,
    required this.currentPath,
    required this.rootPath,
    required this.onGoUp,
    super.key,
  });

  final bool navEnabled;
  final String currentPath;

  /// The lowest folder the caller can open — empty for the real root.
  final String rootPath;
  final VoidCallback onGoUp;

  @override
  Widget build(BuildContext context) {
    final canGoUp =
        navEnabled && currentPath.isNotEmpty && currentPath != rootPath;
    final parent = parentPath(currentPath);
    final parentName = parent.isEmpty
        ? 'Files'
        : parent.substring(parent.lastIndexOf('/') + 1);
    return QuarkBarIconButton(
      key: const ValueKey('file_top_bar_up'),
      icon: QuarkIcons.arrow_back_rounded,
      onPressed: canGoUp ? onGoUp : null,
      tooltip: canGoUp ? 'Back to $parentName' : null,
    );
  }
}

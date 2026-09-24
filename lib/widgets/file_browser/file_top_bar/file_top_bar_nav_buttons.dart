import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Up one level. There is no separate Back: folder navigation replaces the
/// route rather than stacking it, so Back could only repeat up (#2314). Web
/// keeps the browser's own Back, which walks the visited-folder URLs.
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
    return QuarkBarIconButton(
      key: const ValueKey('file_top_bar_up'),
      icon: QuarkIcons.arrow_upward_rounded,
      onPressed: canGoUp ? onGoUp : null,
      tooltip: 'Up one level',
    );
  }
}

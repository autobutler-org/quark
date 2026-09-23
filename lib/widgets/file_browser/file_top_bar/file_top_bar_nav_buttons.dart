import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Back and up. Back and up both go up one level: the browser has no
/// history of its own, and the arrow the user reaches for should not depend on
/// which one they picked.
///
/// Both stop at [rootPath], the lowest folder the caller can open, so a member
/// pressing up in their own files is not walked into the `users` folder they
/// have no use for (#2139).
///
/// Probe keys: `file_top_bar_back` and `file_top_bar_up`.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: QuarkTokens.of(context).spacingXs,
      children: [
        QuarkBarIconButton(
          key: const ValueKey('file_top_bar_back'),
          icon: QuarkIcons.arrow_back_rounded,
          onPressed: canGoUp ? onGoUp : null,
          tooltip: 'Back',
        ),
        QuarkBarIconButton(
          key: const ValueKey('file_top_bar_up'),
          icon: QuarkIcons.arrow_upward_rounded,
          onPressed: canGoUp ? onGoUp : null,
          tooltip: 'Up one level',
        ),
      ],
    );
  }
}

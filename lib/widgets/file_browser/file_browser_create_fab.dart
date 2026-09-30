import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The mobile "Create" button. It fades out while the user scrolls down the
/// listing rather than disappearing, so a scroll back up brings it straight
/// back where it was. Under reduced motion it appears and disappears at once.
class FileBrowserCreateFab extends StatelessWidget {
  const FileBrowserCreateFab({
    required this.visible,
    required this.onPressed,
    super.key,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: reduceMotionOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: IgnorePointer(
        ignoring: !visible,
        child: FloatingActionButton(
          heroTag: 'create_fab',
          onPressed: onPressed,
          tooltip: 'Create',
          child: const Icon(QuarkIcons.add_rounded),
        ),
      ),
    );
  }
}

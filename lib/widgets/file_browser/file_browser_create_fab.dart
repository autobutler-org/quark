import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

/// The mobile "Create" button. It fades out while the user scrolls down the
/// listing rather than disappearing, so a scroll back up brings it straight
/// back where it was.
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
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: IgnorePointer(
        ignoring: !visible,
        child: FloatingActionButton(
          heroTag: 'create_fab',
          onPressed: onPressed,
          tooltip: 'Create',
          child: const Icon(QuarkIcons.add),
        ),
      ),
    );
  }
}

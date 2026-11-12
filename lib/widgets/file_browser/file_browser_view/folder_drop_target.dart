import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

/// Makes one folder row a drop target of its own, so a drag released over a
/// folder uploads into it rather than into the folder being browsed.
class FolderDropTarget extends StatefulWidget {
  const FolderDropTarget({
    required this.targetPath,
    required this.onDropToFolder,
    this.onFolderDragEnter,
    this.onFolderDragExit,
    required this.child,
    super.key,
  });

  final String targetPath;
  final Future<void> Function(List<DropItem> droppedItems, String targetPath)
  onDropToFolder;
  final VoidCallback? onFolderDragEnter;
  final VoidCallback? onFolderDragExit;
  final Widget child;

  @override
  State<FolderDropTarget> createState() => _FolderDropTargetState();
}

class _FolderDropTargetState extends State<FolderDropTarget>
    with SafeSetStateMixin {
  bool _isDragOver = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) {
        if (!mounted) return;
        setStateSafely(() => _isDragOver = true);
        widget.onFolderDragEnter?.call();
      },
      onDragExited: (_) {
        if (!mounted) return;
        setStateSafely(() => _isDragOver = false);
        widget.onFolderDragExit?.call();
      },
      onDragDone: (details) async {
        if (mounted) setStateSafely(() => _isDragOver = false);
        widget.onFolderDragExit?.call();
        await widget.onDropToFolder(details.files, widget.targetPath);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isDragOver ? colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
          color: _isDragOver
              ? colorScheme.primaryContainer.withValues(alpha: 0.35)
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

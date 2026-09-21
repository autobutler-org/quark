import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

/// Makes [child] take files dragged in from the desktop, outlining it while a
/// drag is over it, and hands what was dropped to [onDrop].
///
/// For a page whose drop needs nothing but the drop itself (#2214). The Files
/// page keeps its own target: it coordinates with per-folder targets and
/// scrolls during a drag.
///
/// Web only, like the Files page's: the desktop_drop package supports native
/// desktop too, but that has not been validated on macOS, Linux or Windows.
class UploadDropZone extends StatefulWidget {
  const UploadDropZone({
    required this.enabled,
    required this.onDrop,
    required this.child,
    super.key,
  });

  /// Whether a drop is taken now — false while an upload is running, say.
  final bool enabled;

  /// Called with everything dropped: files, and folders with their contents.
  final ValueChanged<List<DropItem>> onDrop;

  final Widget child;

  @override
  State<UploadDropZone> createState() => _UploadDropZoneState();
}

class _UploadDropZoneState extends State<UploadDropZone>
    with SafeSetStateMixin {
  bool _isDragging = false;

  void _setDragging(bool dragging) {
    if (!mounted) return;
    setStateSafely(() => _isDragging = dragging);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DropTarget(
      enable: kIsWeb && widget.enabled,
      onDragEntered: (_) => _setDragging(true),
      onDragExited: (_) => _setDragging(false),
      onDragDone: (details) {
        _setDragging(false);
        if (details.files.isNotEmpty) widget.onDrop(details.files);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_isDragging)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.primary, width: 1.5),
                  color: colorScheme.primaryContainer.withValues(alpha: 0.20),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

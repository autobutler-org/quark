import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The slide editor's keyboard history: Ctrl+Z (Cmd+Z on a Mac) undoes, and
/// Ctrl+Shift+Z, Cmd+Shift+Z or Ctrl+Y redoes, wherever focus is inside
/// [child] — on the canvas or in the slide panel.
///
/// The canvas handles its own keys first and leaves these alone, so they
/// bubble up to here. A text field inside [child] keeps them: undoing in
/// the middle of typing takes back the typing, not the last slide edit.
///
/// ```dart
/// SlideEditorShortcuts(onUndo: c.undo, onRedo: c.redo, child: body);
/// ```
class SlideEditorShortcuts extends StatelessWidget {
  /// Routes the history keys pressed inside [child] to [onUndo] and
  /// [onRedo].
  const SlideEditorShortcuts({
    required this.onUndo,
    required this.onRedo,
    required this.child,
    super.key,
  });

  /// Takes back the last edit.
  final VoidCallback onUndo;

  /// Puts back what [onUndo] took.
  final VoidCallback onRedo;

  /// The editor the shortcuts cover.
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (node, event) {
      if (event is KeyUpEvent) return KeyEventResult.ignored;
      final typing = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>();
      if (typing != null) return KeyEventResult.ignored;
      final keys = HardwareKeyboard.instance;
      if (!(keys.isControlPressed || keys.isMetaPressed) || keys.isAltPressed) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.keyZ && !keys.isShiftPressed) {
        onUndo();
      } else if (key == LogicalKeyboardKey.keyZ ||
          (key == LogicalKeyboardKey.keyY && keys.isControlPressed)) {
        onRedo();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    },
    child: child,
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The slide editor's find keys: Ctrl+F (Cmd+F on a Mac) runs [onFind] and
/// Ctrl+H (Cmd+H) runs [onReplace], wherever focus is inside [child] — on
/// the canvas, in the slide panel, in the notes or in the find bar itself.
///
/// The canvas handles its own keys first and leaves these alone, so they
/// bubble up to here.
///
/// ```dart
/// SlideFindShortcuts(
///   onFind: find.open,
///   onReplace: () => find.open(replace: true),
///   child: body,
/// );
/// ```
class SlideFindShortcuts extends StatelessWidget {
  /// Routes the find keys pressed inside [child] to [onFind] and
  /// [onReplace].
  const SlideFindShortcuts({
    required this.onFind,
    required this.onReplace,
    required this.child,
    super.key,
  });

  /// Opens the find bar.
  final VoidCallback onFind;

  /// Opens the find bar with its replace row.
  final VoidCallback onReplace;

  /// The editor the keys cover.
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (node, event) {
      if (event is KeyUpEvent) return KeyEventResult.ignored;
      final keys = HardwareKeyboard.instance;
      if (!(keys.isControlPressed || keys.isMetaPressed) ||
          keys.isAltPressed ||
          keys.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.keyF) {
        onFind();
      } else if (key == LogicalKeyboardKey.keyH) {
        onReplace();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    },
    child: child,
  );
}

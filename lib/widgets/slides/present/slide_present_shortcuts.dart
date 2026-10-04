import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The keys that run a presentation (#1165), wherever focus is inside
/// [child]: Right, Space, Page Down and Enter step forward; Left, Page Up and
/// Backspace step back; Home and End jump to the first and last slide;
/// Escape ends the show; F toggles fullscreen.
///
/// It takes focus when it is built, so the keys work the moment the show
/// starts. A held key repeats the step, as a clicker's does. Keys pressed
/// with Ctrl, Cmd or Alt are left alone, so the browser's and the system's
/// own shortcuts still work.
///
/// ```dart
/// SlidePresentShortcuts(
///   onNext: c.next,
///   onPrevious: c.previous,
///   onFirst: c.first,
///   onLast: c.last,
///   onExit: exit,
///   child: body,
/// );
/// ```
class SlidePresentShortcuts extends StatelessWidget {
  /// Routes the presenting keys pressed inside [child].
  const SlidePresentShortcuts({
    required this.onNext,
    required this.onPrevious,
    required this.onFirst,
    required this.onLast,
    required this.onExit,
    required this.child,
    this.onToggleFullscreen,
    super.key,
  });

  /// Shows the next slide.
  final VoidCallback onNext;

  /// Shows the previous slide.
  final VoidCallback onPrevious;

  /// Shows the first slide.
  final VoidCallback onFirst;

  /// Shows the last slide.
  final VoidCallback onLast;

  /// Ends the show.
  final VoidCallback onExit;

  /// Enters or leaves fullscreen; null where the platform has none, and F
  /// does nothing.
  final VoidCallback? onToggleFullscreen;

  /// The show the keys drive.
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event is KeyUpEvent) return KeyEventResult.ignored;
      final keys = HardwareKeyboard.instance;
      if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
        return KeyEventResult.ignored;
      }
      final action = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowRight ||
        LogicalKeyboardKey.space ||
        LogicalKeyboardKey.pageDown ||
        LogicalKeyboardKey.enter ||
        LogicalKeyboardKey.numpadEnter => onNext,
        LogicalKeyboardKey.arrowLeft ||
        LogicalKeyboardKey.pageUp ||
        LogicalKeyboardKey.backspace => onPrevious,
        LogicalKeyboardKey.home => onFirst,
        LogicalKeyboardKey.end => onLast,
        // Neither of these should fire again while the key is held.
        LogicalKeyboardKey.escape when event is KeyDownEvent => onExit,
        LogicalKeyboardKey.keyF when event is KeyDownEvent =>
          onToggleFullscreen,
        _ => null,
      };
      if (action == null) return KeyEventResult.ignored;
      action();
      return KeyEventResult.handled;
    },
    child: child,
  );
}

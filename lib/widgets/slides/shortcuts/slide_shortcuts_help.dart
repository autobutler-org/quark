import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'slide_shortcuts_help_action.dart';
import 'slide_shortcuts_help_intent.dart';

/// Opens the keyboard shortcuts dialog with `?` (Shift+/) or F1, wherever
/// focus is inside [child] (#1168).
///
/// The one line the editor page adds: wrap the editor body in it.
///
/// ```dart
/// SlideShortcutsHelp(child: body);
/// ```
class SlideShortcutsHelp extends StatelessWidget {
  /// Binds `?` and F1 inside [child].
  const SlideShortcutsHelp({required this.child, super.key});

  /// The editor the keys cover.
  final Widget child;

  /// The keys that ask for help.
  static const Map<ShortcutActivator, Intent> bindings = {
    CharacterActivator('?'): SlideShortcutsHelpIntent(fromCharacter: true),
    SingleActivator(LogicalKeyboardKey.f1): SlideShortcutsHelpIntent(),
  };

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: bindings,
    child: Actions(
      actions: {SlideShortcutsHelpIntent: SlideShortcutsHelpAction(context)},
      child: child,
    ),
  );
}

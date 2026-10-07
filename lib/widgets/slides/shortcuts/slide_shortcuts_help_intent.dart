import 'package:flutter/widgets.dart';

/// Asks for the keyboard shortcuts dialog. [SlideShortcutsHelp] binds it to
/// `?` and F1.
class SlideShortcutsHelpIntent extends Intent {
  /// An intent to open the dialog. [fromCharacter] marks the `?` key, which
  /// is also a letter someone may be typing.
  const SlideShortcutsHelpIntent({this.fromCharacter = false});

  /// Whether the `?` key sent it, so it must stand aside for a text field.
  final bool fromCharacter;
}

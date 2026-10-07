import 'package:flutter/material.dart';

import 'slide_shortcuts_dialog.dart';
import 'slide_shortcuts_help_intent.dart';

/// Opens the [SlideShortcutsDialog] for a [SlideShortcutsHelpIntent].
///
/// The `?` key stays out of the way while a text field has focus, so the
/// character can still be typed; F1 opens the dialog from anywhere.
class SlideShortcutsHelpAction extends Action<SlideShortcutsHelpIntent> {
  /// An action that shows the dialog above [context].
  SlideShortcutsHelpAction(this.context);

  /// Where the dialog is shown from.
  final BuildContext context;

  @override
  bool isEnabled(SlideShortcutsHelpIntent intent) =>
      !intent.fromCharacter ||
      FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<EditableText>() ==
          null;

  @override
  Object? invoke(SlideShortcutsHelpIntent intent) {
    SlideShortcutsDialog.show(context);
    return null;
  }
}

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The expanded inline search field, as tall as a bar button so it lines up
/// with the rest of the bar.
class FileTopBarSearchField extends StatelessWidget {
  const FileTopBarSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: QuarkBarIconButton.size,
      child: Focus(
        // Handle ESC to close without needing a separate KeyboardListener
        // (which requires a managed FocusNode that would outlive rebuilds).
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: QuarkSearchField(
          controller: controller,
          focusNode: focusNode,
          hintText: 'Search files…',
          onChanged: onChanged,
          onDismiss: onClose,
          dismissTooltip: 'Close search',
        ),
      ),
    );
  }
}

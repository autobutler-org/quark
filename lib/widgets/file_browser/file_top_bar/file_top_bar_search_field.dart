import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark_icons/quark_icons.dart';
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
    final tokens = QuarkTokens.of(context);
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
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: false,
          decoration: InputDecoration(
            hintText: 'Search files…',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            prefixIcon: Icon(
              QuarkIcons.search_rounded,
              size: 18,
              color: tokens.secondaryForeground,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                QuarkIcons.close_rounded,
                size: 16,
                color: tokens.secondaryForeground,
              ),
              tooltip: 'Close search',
              onPressed: onClose,
            ),
            filled: true,
            fillColor: tokens.input,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              borderSide: BorderSide(color: tokens.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              borderSide: BorderSide(color: tokens.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              borderSide: BorderSide(color: tokens.primary),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

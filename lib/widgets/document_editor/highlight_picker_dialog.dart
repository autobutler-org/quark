import 'package:flutter/material.dart';

/// Picks a highlight color for the current selection.
///
/// Pops the chosen color, [Colors.transparent] for "Clear", or null when
/// canceled. Each swatch is named by its tooltip, so a screen reader reads
/// "Yellow" rather than an unlabeled button.
class HighlightPickerDialog extends StatelessWidget {
  const HighlightPickerDialog({super.key});

  static const _colors = <String, Color>{
    'Yellow': Color(0xFFFFEB3B),
    'Green': Color(0xFF8BC34A),
    'Blue': Color(0xFF4FC3F7),
    'Pink': Color(0xFFF48FB1),
    'Lavender': Color(0xFFCE93D8),
    'Orange': Color(0xFFFFCC80),
    'Red': Color(0xFFEF9A9A),
    'Cyan': Color(0xFF80DEEA),
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Highlight color'),
      content: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _colors.entries.map((entry) {
          return Tooltip(
            message: entry.key,
            child: Semantics(
              button: true,
              child: GestureDetector(
                key: ValueKey('highlight_swatch_${entry.key.toLowerCase()}'),
                onTap: () => Navigator.of(context).pop(entry.value),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black26, width: 1.5),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(Colors.transparent),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

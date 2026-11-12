import 'package:material_ui/material_ui.dart';

/// Picks a highlight color for the current selection.
///
/// Pops the chosen color, [Colors.transparent] for "Clear", or null when
/// cancelled.
class HighlightPickerDialog extends StatelessWidget {
  const HighlightPickerDialog({super.key});

  static const _colors = <Color>[
    Color(0xFFFFEB3B), // Yellow
    Color(0xFF8BC34A), // Green
    Color(0xFF4FC3F7), // Blue
    Color(0xFFF48FB1), // Pink
    Color(0xFFCE93D8), // Lavender
    Color(0xFFFFCC80), // Orange
    Color(0xFFEF9A9A), // Red
    Color(0xFF80DEEA), // Cyan
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Highlight color'),
      content: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _colors.map((c) {
          return GestureDetector(
            onTap: () => Navigator.of(context).pop(c),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black26, width: 1.5),
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

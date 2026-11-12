import 'package:material_ui/material_ui.dart';

/// One key-and-description row of the viewer's keyboard shortcuts dialog.
class ShortcutRow extends StatelessWidget {
  final String shortcut;
  final String description;

  const ShortcutRow({
    super.key,
    required this.shortcut,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              shortcut,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(description, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One icon-and-label pair in the document editor's status bar. The label
/// trails off in an ellipsis when the bar is too narrow for it.
class DocumentStatusItem extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Tints the icon only — the label always follows the surrounding theme.
  final Color color;

  const DocumentStatusItem({
    required this.icon,
    required this.label,
    required this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: QuarkTokens.of(context).mutedForeground,
            ),
          ),
        ),
      ],
    );
  }
}

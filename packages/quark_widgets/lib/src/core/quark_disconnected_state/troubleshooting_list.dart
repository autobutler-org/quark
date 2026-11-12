import 'package:material_ui/material_ui.dart';

import '../../theme/quark_tokens.dart';

/// The bulleted checklist, left-aligned so the lines scan as a list rather
/// than as more centered prose.
class TroubleshootingList extends StatelessWidget {
  /// Creates the checklist rendering [steps].
  const TroubleshootingList({required this.steps, super.key});

  /// The troubleshooting steps, one bullet each.
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final style = TextStyle(
      fontSize: 14,
      height: 1.5,
      color: colorScheme.onSurface.withValues(alpha: 0.7),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in steps)
          Padding(
            padding: EdgeInsets.only(bottom: tokens.spacingSm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Excluded from semantics so a screen reader announces the
                // step, not a bullet character before every line.
                ExcludeSemantics(child: Text('•  ', style: style)),
                Expanded(child: Text(step, style: style)),
              ],
            ),
          ),
      ],
    );
  }
}

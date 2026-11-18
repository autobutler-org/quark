import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// A strip above a message composer saying what the next send does to an
/// existing message, such as editing it (#2426), with a button to stop.
///
/// [title] says what is happening ("Editing message") and [text], when set,
/// is one line of the message it is about, cut short with an ellipsis. The
/// close button fires [onCancel]; what stopping means is the caller's, and
/// so is Escape. Nothing animates.
///
/// Key prefixes: `composer_context` on the strip and
/// `composer_context_cancel` on its close button.
///
/// ```dart
/// QuarkComposerContextBar(
///   icon: QuarkIcons.edit_outlined,
///   title: 'Editing message',
///   text: 'Dinner at 7',
///   onCancel: controller.cancelEdit,
/// );
/// ```
class QuarkComposerContextBar extends StatelessWidget {
  /// Creates the strip for [title].
  const QuarkComposerContextBar({
    required this.icon,
    required this.title,
    required this.onCancel,
    this.text,
    this.cancelTooltip = 'Cancel',
    super.key,
  });

  /// The glyph at the strip's start.
  final IconData icon;

  /// What the next send does, in a few words.
  final String title;

  /// One line of the message it is about. Null or empty shows only [title].
  final String? text;

  /// Called when the close button is pressed.
  final VoidCallback onCancel;

  /// The close button's tooltip.
  final String cancelTooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final text = this.text;
    return Container(
      key: const ValueKey('composer_context'),
      decoration: BoxDecoration(
        color: tokens.card,
        border: BorderDirectional(
          start: BorderSide(color: tokens.primary, width: 3),
        ),
      ),
      padding: EdgeInsetsDirectional.only(start: tokens.spacingSm),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tokens.mutedForeground),
          SizedBox(width: tokens.spacingSm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                if (text != null && text.isNotEmpty)
                  Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.mutedForeground),
                  ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('composer_context_cancel'),
            tooltip: cancelTooltip,
            iconSize: 18,
            color: tokens.mutedForeground,
            icon: const Icon(QuarkIcons.close),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

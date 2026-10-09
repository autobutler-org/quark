import 'package:flutter/material.dart';
import 'package:quark/widgets/document_editor/document_status_item.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The strip under the document: page brightness, word count, and save state.
class DocumentStatusBar extends StatelessWidget {
  /// Page brightness, chosen independently of the global theme toggle (#938).
  final bool darkPage;
  final VoidCallback onToggleDarkPage;
  final int wordCount;
  final bool isReadOnly;
  final bool dirty;

  const DocumentStatusBar({
    required this.darkPage,
    required this.onToggleDarkPage,
    required this.wordCount,
    required this.isReadOnly,
    required this.dirty,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final muted = tokens.mutedForeground;

    // The toggle's 48dp target reaches 12px past its 24px glyph box, so the
    // bar's left padding gives those 12px back and the glyph stays where it
    // was. No vertical padding: the target is the bar's height (#2605).
    return Padding(
      padding: const EdgeInsets.only(
        left: 24 - (kMinInteractiveDimension - 24) / 2,
        right: 24,
      ),
      child: Row(
        children: [
          // The left group gives up its labels to an ellipsis on a phone,
          // rather than pushing the save state off the edge.
          Expanded(
            child: Row(
              children: [
                // Page brightness toggle (#938) — bottom-left, near the page
                IconButton(
                  icon: Icon(
                    darkPage
                        ? QuarkIcons.light_mode_outlined
                        : QuarkIcons.dark_mode_outlined,
                    size: 14,
                  ),
                  tooltip: darkPage
                      ? 'Switch to light page'
                      : 'Switch to dark page',
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    // A 24px glyph box inside a 48dp touch target, on every
                    // platform (#2605).
                    minimumSize: const Size(24, 24),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  color: muted,
                  onPressed: onToggleDarkPage,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: DocumentStatusItem(
                    icon: QuarkIcons.edit_note,
                    label: '$wordCount words',
                    color: muted,
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: DocumentStatusItem(
                    icon: QuarkIcons.lock_outline,
                    label: 'Private',
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (isReadOnly)
            DocumentStatusItem(
              icon: QuarkIcons.visibility_outlined,
              label: 'Read-only',
              color: muted,
            )
          else if (dirty)
            DocumentStatusItem(
              icon: QuarkIcons.circle,
              label: 'Unsaved',
              color: tokens.warning,
            )
          else
            DocumentStatusItem(
              icon: QuarkIcons.check_circle_outline,
              label: 'Saved',
              color: tokens.success,
            ),
        ],
      ),
    );
  }
}

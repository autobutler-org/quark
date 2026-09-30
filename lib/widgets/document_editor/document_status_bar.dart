import 'package:flutter/material.dart';
import 'package:quark/widgets/document_editor/document_status_item.dart';
import 'package:quark_icons/quark_icons.dart';

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
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.5);

    return Padding(
      // No vertical padding: the toggle's 48 pixel tap target (#2605) sets
      // the bar's height.
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
            tooltip: darkPage ? 'Switch to light page' : 'Switch to dark page',
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(24, 24),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            color: muted,
            onPressed: onToggleDarkPage,
          ),
          const SizedBox(width: 8),
          // Takes the width the save state leaves, and cuts its labels short
          // on a phone rather than overflowing the bar.
          Expanded(
            child: Row(
              children: [
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
          if (isReadOnly)
            DocumentStatusItem(
              icon: QuarkIcons.visibility_outlined,
              label: 'Read-only',
              color: muted,
            )
          else if (dirty)
            const DocumentStatusItem(
              icon: QuarkIcons.circle,
              label: 'Unsaved',
              color: Color(0xFFF59E0B),
            )
          else
            const DocumentStatusItem(
              icon: QuarkIcons.check_circle_outline,
              label: 'Saved',
              color: Color(0xFF10B981),
            ),
        ],
      ),
    );
  }
}

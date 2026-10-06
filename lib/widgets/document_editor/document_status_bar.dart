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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            color: muted,
            onPressed: onToggleDarkPage,
          ),
          const SizedBox(width: 8),
          DocumentStatusItem(
            icon: QuarkIcons.edit_note,
            label: '$wordCount words',
            color: muted,
          ),
          const SizedBox(width: 16),
          DocumentStatusItem(
            icon: QuarkIcons.lock_outline,
            label: 'Private',
            color: muted,
          ),
          const Spacer(),
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

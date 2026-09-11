import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// The top bar shown in place of the usual file chrome while multi-select is
/// active: cancel, a count, select-all, and delete, with restore in front of
/// delete when [onRestore] is given (the trash offers both).
///
/// This is custom chrome rather than a real [AppBar], so it consults the
/// display insets itself: the [SafeArea] inside is what keeps the controls
/// clear of the status bar, notch, or Dynamic Island (#1597). The surface color
/// sits on the outer container so the inset region is painted rather than
/// left showing whatever is behind the bar.
///
/// Key prefixes: `file_selection_cancel`, `file_selection_toggle_all`,
/// `file_selection_restore`, and `file_selection_delete`.
///
/// ```dart
/// FileSelectionBar(
///   selectedCount: controller.selected.length,
///   totalCount: controller.files.length,
///   onSelectAll: controller.selectAll,
///   onDeselectAll: controller.deselectAll,
///   onCancel: controller.exitSelection,
///   onDelete: controller.deleteSelected,
/// );
/// ```
class FileSelectionBar extends StatelessWidget {
  /// Creates the selection bar for a listing of [totalCount] entries.
  const FileSelectionBar({
    required this.selectedCount,
    required this.totalCount,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onCancel,
    this.onDelete,
    this.onRestore,
    this.deleteTooltip = 'Delete selected',
    super.key,
  });

  /// How many entries are selected, shown in the count label.
  final int selectedCount;

  /// How many entries the listing holds, which decides whether the button
  /// offers "Select all" or "Deselect all".
  final int totalCount;

  /// Selects every entry. Called only while some are unselected.
  final VoidCallback onSelectAll;

  /// Clears the selection but stays in selection mode. Called only once
  /// everything is selected.
  final VoidCallback onDeselectAll;

  /// Leaves selection mode entirely.
  final VoidCallback onCancel;

  /// Deletes the selection. Null renders the delete button disabled and dimmed,
  /// for a selection that cannot be deleted.
  final VoidCallback? onDelete;

  /// Restores the selection. Null leaves the restore button out entirely,
  /// which is every listing except the trash.
  final VoidCallback? onRestore;

  /// The delete button's tooltip, for a listing where delete means something
  /// stronger — "Delete permanently" in the trash.
  final String deleteTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);

    return Container(
      color: colors.surfaceContainerHighest,
      // `bottom: false` because this bar only ever sits at the top of the
      // page; the left/right insets still apply, which is what keeps the
      // controls clear of the notch in landscape.
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingSm),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('file_selection_cancel'),
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel selection',
                  onPressed: onCancel,
                ),
                // Flexible so the count is clipped on a narrow phone rather
                // than pushing the actions off the row (#1599).
                Flexible(
                  child: Text(
                    '$selectedCount selected',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                TextButton(
                  key: const ValueKey('file_selection_toggle_all'),
                  onPressed: selectedCount < totalCount
                      ? onSelectAll
                      : onDeselectAll,
                  child: Text(
                    selectedCount < totalCount ? 'Select all' : 'Deselect all',
                  ),
                ),
                SizedBox(width: tokens.spacingXs),
                if (onRestore != null)
                  IconButton(
                    key: const ValueKey('file_selection_restore'),
                    icon: const Icon(Icons.restore),
                    tooltip: 'Restore selected',
                    onPressed: onRestore,
                  ),
                IconButton(
                  key: const ValueKey('file_selection_delete'),
                  icon: Icon(
                    Icons.delete_outline,
                    color: onDelete != null
                        ? colors.error
                        : colors.onSurface.withValues(alpha: 0.38),
                  ),
                  tooltip: deleteTooltip,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

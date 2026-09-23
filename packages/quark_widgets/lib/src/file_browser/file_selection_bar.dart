import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../layout/quark_bar_chip.dart';
import '../layout/quark_bar_icon_button.dart';
import '../theme/quark_tokens.dart';

/// The top bar shown in place of the usual chrome while multi-select is
/// active: cancel, a count, select-all, and delete, with restore in front of
/// delete when [onRestore] is given (the trash offers both).
///
/// Files, the trash and Photos all select through this one bar, so selecting
/// looks the same everywhere (#2311): the same leading close button, the
/// count, "Select all", and the page's own [actions]. It wears the app bar's
/// background and hairline and uses the bar buttons, so swapping it in for
/// the page's bar changes the controls, not the chrome.
///
/// This is custom chrome rather than a real [AppBar], so it consults the
/// display insets itself: the [SafeArea] inside is what keeps the controls
/// clear of the status bar, notch, or Dynamic Island (#1597). The surface color
/// sits on the outer container so the inset region is painted rather than
/// left showing whatever is behind the bar. It is also a
/// [PreferredSizeWidget], so it can stand in a `Scaffold`'s app bar slot.
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
class FileSelectionBar extends StatelessWidget implements PreferredSizeWidget {
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
    this.showDelete = true,
    this.title,
    this.actions = const [],
    super.key,
  });

  /// The bar's height below any top inset.
  static const double height = 56;

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

  /// Whether the listing deletes at all. False leaves the delete button out,
  /// for a selection that is headed somewhere else, such as Photos' albums.
  final bool showDelete;

  /// Replaces the "N selected" label, for a selection with a purpose to name,
  /// such as "Adding to Hiking". Null shows the count.
  final String? title;

  /// The page's own bar buttons, rendered after "Select all" and before
  /// restore and delete.
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final everything = selectedCount >= totalCount;

    return Container(
      color: tokens.sidebar,
      // A foreground border, so the hairline does not pad the bar a pixel
      // taller than the bar it replaces.
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      // `bottom: false` because this bar only ever sits at the top of the
      // page; the left/right insets still apply, which is what keeps the
      // controls clear of the notch in landscape.
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingSm),
            child: Row(
              spacing: tokens.spacingXs,
              children: [
                QuarkBarIconButton(
                  key: const ValueKey('file_selection_cancel'),
                  icon: QuarkIcons.close_rounded,
                  tooltip: 'Cancel selection',
                  onPressed: onCancel,
                ),
                // Expanded so the count is clipped on a narrow phone rather
                // than pushing the actions off the row (#1599), and so it is
                // the only flex child: beside a Spacer it was allotted half
                // the free width, used a sliver of it, and left the actions
                // stranded mid-row (#2246).
                Expanded(
                  child: Text(
                    title ?? '$selectedCount selected',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: tokens.foreground),
                  ),
                ),
                QuarkBarChip(
                  key: const ValueKey('file_selection_toggle_all'),
                  icon: everything
                      ? QuarkIcons.circle_outlined
                      : QuarkIcons.check_circle_rounded,
                  label: everything ? 'Deselect all' : 'Select all',
                  keepLabel: true,
                  onPressed: everything ? onDeselectAll : onSelectAll,
                ),
                ...actions,
                if (onRestore != null)
                  QuarkBarIconButton(
                    key: const ValueKey('file_selection_restore'),
                    icon: QuarkIcons.restore,
                    tooltip: 'Restore selected',
                    onPressed: onRestore,
                  ),
                if (showDelete)
                  QuarkBarIconButton(
                    key: const ValueKey('file_selection_delete'),
                    icon: QuarkIcons.delete_outline,
                    tooltip: deleteTooltip,
                    destructive: true,
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

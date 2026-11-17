import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';

/// The row over a phone's file list: where the user is on the left, and a
/// "Sort and view" chip on the right that reads the current sort (#4226).
///
/// It stands in for the column headers, which a one-line-per-file list has
/// no columns for. The chip only reports the tap; the caller opens whatever
/// it opens, usually a `FileSortViewSheet` in a sheet.
///
/// [lead] takes what is left after the chip and should cut itself short,
/// as a breadcrumb does.
///
/// Key prefixes: `file_sort_view_chip` on the chip.
///
/// ```dart
/// FileSortViewBar(
///   lead: breadcrumb,
///   sortLabel: 'Name',
///   ascending: true,
///   onPressed: openSortSheet,
/// );
/// ```
class FileSortViewBar extends StatelessWidget {
  /// Creates the row with [lead] beside a chip reading [sortLabel].
  const FileSortViewBar({
    required this.lead,
    required this.sortLabel,
    required this.ascending,
    required this.onPressed,
    super.key,
  });

  /// The height of the row: the chip's 48dp touch target.
  static const double height = 48;

  /// Where the listing is, usually a breadcrumb.
  final Widget lead;

  /// The name of what the list is sorted by, shown on the chip.
  final String sortLabel;

  /// Whether that sort runs ascending; read out with the label.
  final bool ascending;

  /// Called when the chip is tapped.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final order = ascending ? 'ascending' : 'descending';
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: tokens.spacingMd,
        end: tokens.spacingSm,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: height),
        child: Row(
          children: [
            Expanded(child: lead),
            SizedBox(width: tokens.spacingSm),
            Semantics(
              label: 'Sort and view, by $sortLabel $order',
              button: true,
              excludeSemantics: true,
              onTap: onPressed,
              child: ActionChip(
                key: const ValueKey('file_sort_view_chip'),
                tooltip: 'Sort and view',
                avatar: Icon(
                  ascending
                      ? QuarkIcons.arrow_upward_rounded
                      : QuarkIcons.arrow_downward_rounded,
                  size: 16,
                ),
                label: Text(sortLabel),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onPressed: onPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../models/duplicate_group_item.dart';
import '../models/duplicate_photo_item.dart';
import '../theme/quark_tokens.dart';
import 'duplicate_group_list/duplicate_delete_bar.dart';
import 'duplicate_group_list/duplicate_group_card.dart';
import 'duplicate_group_list/duplicate_suggestion_header.dart';

/// Groups of duplicate photos, each copy marked Keep or Delete (#1666).
///
/// Holds nothing: which copies are marked comes in as [selectedIds], a tap on
/// a copy goes out through [onToggle]. Each group keeps at least one copy, so
/// its last kept copy cannot be marked. Loading, the error, and an empty
/// result each have their own state.
///
/// The delete bar shows only while a copy is marked (#3362), counting the
/// marked copies and the groups they are in, since some may be scrolled out
/// of view; its button calls [onDeleteSelected]. With [onSelectSuggested], a
/// row above the groups offers to mark the suggested copies.
///
/// Key prefixes: `duplicate_group_<id>` on each group,
/// `duplicate_photo_<id>` on each copy, `duplicates_select_suggested` on the
/// suggestion button, and `duplicates_selection_summary`,
/// `duplicates_clear_selection` and `duplicates_delete` on the delete bar.
///
/// ```dart
/// DuplicateGroupList(
///   groups: controller.groups,
///   selectedIds: controller.selectedIds,
///   thumbnailBuilder: (context, photo) => Image.network(urlFor(photo)),
///   onToggle: controller.toggle,
///   onDeleteSelected: confirmAndDelete,
///   onSelectSuggested: controller.selectSuggested,
///   onClearSelection: controller.clearSelection,
/// );
/// ```
class DuplicateGroupList extends StatelessWidget {
  /// Creates the list over [groups].
  const DuplicateGroupList({
    required this.groups,
    required this.selectedIds,
    required this.thumbnailBuilder,
    required this.onToggle,
    required this.onDeleteSelected,
    this.onSelectSuggested,
    this.onClearSelection,
    this.isLoading = false,
    this.isDeleting = false,
    this.error,
    super.key,
  });

  /// The groups, in order.
  final List<DuplicateGroupItem> groups;

  /// The [DuplicatePhotoItem.id]s marked for deletion.
  final Set<String> selectedIds;

  /// Builds a copy's thumbnail. The caller supplies the image.
  final Widget Function(BuildContext context, DuplicatePhotoItem photo)
  thumbnailBuilder;

  /// Called with the id of a copy that was tapped.
  final ValueChanged<String> onToggle;

  /// Called when the delete button is tapped.
  final VoidCallback onDeleteSelected;

  /// Called when Select suggested is tapped. Null hides the row offering it,
  /// for when there is nothing left to suggest.
  final VoidCallback? onSelectSuggested;

  /// Called when the delete bar's Clear is tapped. Null hides Clear.
  final VoidCallback? onClearSelection;

  /// Whether the groups are loading. Shows a loader while there are none.
  final bool isLoading;

  /// Whether a delete is running, which busies the button.
  final bool isDeleting;

  /// A user-facing message for a load that failed, or null.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;

    if (isLoading && groups.isEmpty) {
      return const Center(child: QuarkLoader());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacingLg),
          child: Text(error, textAlign: TextAlign.center),
        ),
      );
    }
    if (groups.isEmpty) {
      return const EmptyStateWidget(
        icon: QuarkIcons.photo_library_outlined,
        headline: 'No duplicates found',
        subtext: 'Photos show up here once their thumbnails have loaded.',
      );
    }

    final onSelectSuggested = this.onSelectSuggested;
    final header = onSelectSuggested == null ? 0 : 1;
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.all(tokens.spacingMd),
            itemCount: groups.length + header,
            separatorBuilder: (_, _) => SizedBox(height: tokens.spacingMd),
            itemBuilder: (context, index) => index < header
                ? DuplicateSuggestionHeader(
                    onSelectSuggested: onSelectSuggested!,
                  )
                : DuplicateGroupCard(
                    group: groups[index - header],
                    selectedIds: selectedIds,
                    thumbnailBuilder: thumbnailBuilder,
                    onToggle: onToggle,
                  ),
          ),
        ),
        if (selectedIds.isNotEmpty)
          DuplicateDeleteBar(
            count: selectedIds.length,
            groupCount: groups
                .where((g) => g.photos.any((p) => selectedIds.contains(p.id)))
                .length,
            onDelete: onDeleteSelected,
            onClear: onClearSelection,
            isDeleting: isDeleting,
          ),
      ],
    );
  }
}

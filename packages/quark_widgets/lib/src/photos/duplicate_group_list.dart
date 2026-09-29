import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../models/duplicate_group_item.dart';
import '../models/duplicate_photo_item.dart';
import '../theme/quark_tokens.dart';
import 'duplicate_group_list/duplicate_group_card.dart';

/// Groups of duplicate photos, each copy marked Keep or Delete, with a button
/// that deletes every copy marked Delete (#1666).
///
/// Holds nothing: which copies are marked comes in as [selectedIds], a tap on
/// a copy goes out through [onToggle], and the button calls
/// [onDeleteSelected]. Each group keeps at least one copy, so its last kept
/// copy cannot be marked. Loading, the error, and an empty result each have
/// their own state.
///
/// Key prefixes: `duplicate_group_<id>` on each group,
/// `duplicate_photo_<id>` on each copy, and `duplicates_delete` on the
/// delete button.
///
/// ```dart
/// DuplicateGroupList(
///   groups: controller.groups,
///   selectedIds: controller.selectedIds,
///   thumbnailBuilder: (context, photo) => Image.network(urlFor(photo)),
///   onToggle: controller.toggle,
///   onDeleteSelected: confirmAndDelete,
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

    final count = selectedIds.length;
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.all(tokens.spacingMd),
            itemCount: groups.length,
            separatorBuilder: (_, _) => SizedBox(height: tokens.spacingMd),
            itemBuilder: (context, index) => DuplicateGroupCard(
              group: groups[index],
              selectedIds: selectedIds,
              thumbnailBuilder: thumbnailBuilder,
              onToggle: onToggle,
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingMd),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('duplicates_delete'),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.error,
                  foregroundColor: tokens.errorForeground,
                ),
                onPressed: count == 0 || isDeleting ? null : onDeleteSelected,
                icon: isDeleting
                    ? const QuarkLoader(size: 20)
                    : const Icon(QuarkIcons.delete_outline),
                label: Text(
                  count == 0
                      ? 'Tap a copy to mark it for deletion'
                      : 'Delete $count ${count == 1 ? 'photo' : 'photos'}',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/location_clusters.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The photos of the cluster chosen on the Locations map or list (#3557),
/// newest first, in the same [PhotoGrid] the library uses. A view of the
/// existing photos: nothing is copied or created by showing them. A tap opens
/// a photo in the viewer; a long press starts selecting, and Add to album
/// adds the selection through the normal album flow.
///
/// [scrollController] is the bottom sheet's on a phone, so dragging the
/// grid up grows the sheet to a full-screen grid.
///
/// Keys: `location_photos`, `location_photos_close`,
/// `location_photos_add_to_album`, and the grid's own.
class LocationPhotosPane extends StatelessWidget {
  /// Creates the pane.
  const LocationPhotosPane({
    required this.cluster,
    required this.photos,
    required this.thumbnailBuilder,
    required this.onOpen,
    required this.onToggleSelection,
    required this.onClose,
    required this.onAddToAlbum,
    this.selectedIds = const {},
    this.columns = 3,
    this.scrollController,
    super.key,
  });

  /// The cluster whose photos these are.
  final LocationCluster cluster;

  /// Its photos, in [cluster]'s order.
  final List<PhotoItem> photos;

  /// A photo's picture.
  final Widget Function(BuildContext context, PhotoItem photo) thumbnailBuilder;

  /// Opens the photo at an index in the viewer.
  final ValueChanged<int> onOpen;

  /// Selects or deselects the photo at an index.
  final ValueChanged<int> onToggleSelection;

  /// Closes the pane, back to the map as it was.
  final VoidCallback onClose;

  /// Adds the selected photos to an album. Shown only with a selection.
  final VoidCallback onAddToAlbum;

  /// The ids of the selected photos.
  final Set<String> selectedIds;

  /// How many photos a row holds.
  final int columns;

  /// The scroll view's controller, the bottom sheet's on a phone.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final selecting = selectedIds.isNotEmpty;
    final title =
        '${cluster.count} ${cluster.count == 1 ? 'photo' : 'photos'} · '
        '${describeDateRange(cluster.earliest, cluster.latest)}';
    return Material(
      key: const ValueKey('location_photos'),
      color: tokens.card,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.spacingMd,
                tokens.spacingSm,
                tokens.spacingSm,
                tokens.spacingSm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                  if (selecting) ...[
                    QuarkBarChip(
                      key: const ValueKey('location_photos_add_to_album'),
                      icon: QuarkIcons.add,
                      label: 'Add to album (${selectedIds.length})',
                      onPressed: onAddToAlbum,
                    ),
                    SizedBox(width: tokens.spacingXs),
                  ],
                  QuarkBarIconButton(
                    key: const ValueKey('location_photos_close'),
                    icon: QuarkIcons.close,
                    tooltip: 'Close',
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
          PhotoGrid(
            photos: photos,
            crossAxisCount: columns,
            selectedIds: selectedIds,
            selectionMode: selecting,
            emptyState: const SizedBox.shrink(),
            thumbnailBuilder: thumbnailBuilder,
            onTap: (i) => selecting ? onToggleSelection(i) : onOpen(i),
            onLongPress: onToggleSelection,
          ),
        ],
      ),
    );
  }
}

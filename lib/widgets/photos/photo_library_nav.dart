import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Photos page's library navigation: the package's
/// [PhotoLibrarySidebar] fed from a [PhotosController], with All photos, the
/// categories and the album tree.
///
/// A wide window shows it as the split view's pane, with the grid-size
/// [sizeControl] at the top. A phone shows it in a `PhotoLibrarySheet`
/// instead of stacking it above the grid, which pushed the first photo
/// halfway down the screen (#4149).
///
/// It reads [controller] when it builds; whoever shows it rebuilds it when
/// the controller changes.
///
/// Key prefixes: none of its own; the sidebar's parts carry theirs.
///
/// ```dart
/// PhotoLibraryNav(
///   controller: controller,
///   onShowAlbum: showAlbum,
///   onCreateAlbum: createAlbum,
///   onAlbumMenu: showAlbumActions,
/// );
/// ```
class PhotoLibraryNav extends StatelessWidget {
  /// Creates the navigation over [controller].
  const PhotoLibraryNav({
    required this.controller,
    required this.onShowAlbum,
    required this.onCreateAlbum,
    required this.onAlbumMenu,
    this.onPicked,
    this.sizeControl,
    super.key,
  });

  /// Where the library and its albums come from.
  final PhotosController controller;

  /// Shows the album with this id, or All photos for null.
  final ValueChanged<int?> onShowAlbum;

  /// Starts making a new top-level album.
  final VoidCallback onCreateAlbum;

  /// Opens an album's menu at a global position.
  final void Function(AlbumItem album, Offset position) onAlbumMenu;

  /// Fires after All photos, a category or an album is picked, after the
  /// pick itself. The sheet closes here.
  final VoidCallback? onPicked;

  /// The grid-size control at the top, or null for none.
  final Widget? sizeControl;

  void _show(int? albumId) {
    onShowAlbum(albumId);
    onPicked?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return PhotoLibrarySidebar(
      sizeControl: sizeControl,
      categories: c.showsCategories
          ? PhotoCategoryList(
              categories: c.categories,
              selectedId: c.selectedCategory.name,
              expanded: c.categoriesExpanded,
              onToggleExpanded: c.toggleCategoriesExpanded,
              onSelected: (id) {
                c.selectCategory(PhotoCategory.values.byName(id));
                onPicked?.call();
              },
            )
          : null,
      albums: AlbumSidebar(
        albums: c.albums,
        isLoading: c.albumsLoading,
        expandedIds: c.expandedAlbumIds,
        shrinkWrap: QuarkSplitView.isCollapsed(context),
        selectedAlbumId: c.selectedAlbumId,
        onAllPhotosSelected: () => _show(null),
        onAlbumSelected: (item) => _show(item.id),
        onToggleExpanded: c.toggleAlbumExpanded,
        onCreateAlbum: onCreateAlbum,
        onAlbumMenu: onAlbumMenu,
        sort: c.albumSort,
        onSortChanged: c.setAlbumSort,
        isSectionExpanded: c.albumsSectionExpanded,
        onToggleSection: c.toggleAlbumsSectionExpanded,
      ),
    );
  }
}

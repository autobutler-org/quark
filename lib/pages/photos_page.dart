import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/pages/album_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/photo_grid_config.dart';
import 'package:quark/utils/quark_widget_items.dart';
import 'package:quark/widgets/device_upload_picker.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/photos/album_actions_sheet.dart';
import 'package:quark/widgets/photos/album_name_dialog.dart';
import 'package:quark/widgets/photos/album_picker_sheet.dart';
import 'package:quark/widgets/photos/delete_album_dialog.dart';
import 'package:quark/widgets/photos/photo_thumbnail.dart';
import 'package:quark/widgets/photos/photos_empty_state.dart';
import 'package:quark/widgets/photos/photos_selection_app_bar.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

class PhotosPage extends StatefulWidget {
  const PhotosPage({this.addingToAlbum, super.key});

  /// When set, the page opens in "adding to album" mode — selection mode is
  /// immediately active and the header shows the album name.
  final PhotoAlbum? addingToAlbum;

  @override
  State<PhotosPage> createState() => PhotosPageState();
}

class PhotosPageState extends State<PhotosPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  final PhotosController _controller = PhotosController();

  // Above-viewport nav: the hidden nav panel is measured once on first layout,
  // then the scroll controller's initial offset is set so the photo grid is
  // flush with the top of the viewport. Scroll up to reveal the nav.
  //
  // We can't know the nav height before layout, so we use a two-pass approach:
  //  1. First render: nav is visible briefly at offset 0
  //  2. After layout: measure nav height, recreate the scroll controller with
  //     that initialScrollOffset, setState to rebuild — nav is now above viewport
  //
  // This is the only reliable way: initialScrollOffset is set before the first
  // frame the user sees (WidgetsBinding post-frame), so there's no visible flash.
  final GlobalKey _navPanelKey = GlobalKey();
  bool _navScrollInitialized = false;
  bool _showScrollHint = true;

  /// Guards [_openPhoto], so a second tap while the bytes are still
  /// downloading cannot push a second viewer.
  bool _isOpeningPhoto = false;

  ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _scheduleNavMeasure();
    final addingTo = widget.addingToAlbum;
    if (addingTo != null) {
      _controller.enterSelectionMode(addingTo: addingTo.toAlbumItem());
    }
  }

  /// Frames to wait for the nav panel to report a size before giving up.
  ///
  /// Every failure path here used to re-post itself unconditionally, so the
  /// three retries below were an unbounded frame loop. It ran forever on
  /// desktop, where the nav panel is never built at all, and forever in compact
  /// mode too while the sidebar's layout error stopped it ever getting a size —
  /// a permanent frame loop behind an already-blank screen. Nothing checked
  /// `mounted` either, so the chain outlived the State it belonged to (#1599).
  static const int _navMeasureMaxFrames = 20;

  /// Whether the most recent build used the compact layout. Only that layout
  /// builds a nav panel, so it is the only one with anything to measure.
  bool _compactLayout = false;
  int _navMeasureAttempts = 0;
  bool _navMeasureScheduled = false;

  /// True once the nav measurement has finished — either it jumped the scroll
  /// view past the nav panel, or it gave up. Either way nothing is still
  /// scheduling frames.
  @visibleForTesting
  bool get navScrollSettled => _navScrollInitialized;

  /// Frames spent waiting for the nav panel to report a size.
  @visibleForTesting
  int get navMeasureAttempts => _navMeasureAttempts;

  /// Schedules a measurement attempt, at most one outstanding at a time.
  void _scheduleNavMeasure() {
    if (_navScrollInitialized || _navMeasureScheduled) return;
    _navMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navMeasureScheduled = false;
      _measureAndJumpNav();
    });
  }

  void _measureAndJumpNav() {
    if (_navScrollInitialized || !mounted) return;
    // Desktop lays the sidebar out in a bounded Row with no nav panel, so
    // there is nothing to measure and nothing to wait for.
    if (!_compactLayout) return;

    void retry() {
      _navMeasureAttempts++;
      if (_navMeasureAttempts >= _navMeasureMaxFrames) {
        // Give up rather than spin. The page simply stays scrolled to the top
        // with the nav panel visible — cosmetic, and the user can scroll.
        _navScrollInitialized = true;
        return;
      }
      _scheduleNavMeasure();
    }

    final box = _navPanelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.height <= 0) {
      // Nav not yet in tree or not yet laid out — retry next frame.
      retry();
      return;
    }
    // Recreate the scroll controller with the nav height as initial offset.
    // This ensures the scroll position starts at the right place even before
    // content has loaded (no dependency on maxScrollExtent).
    final oldController = _scrollController;
    final newController = ScrollController(
      initialScrollOffset: box.size.height,
    );
    newController.addListener(_onScroll);
    setState(() {
      _scrollController = newController;
      _navScrollInitialized = true;
    });
    oldController.removeListener(_onScroll);
    oldController.dispose();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final currentScroll = _scrollController.position.pixels;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // Try to initialize the nav scroll if it hasn't happened yet (photos may
    // have loaded after the first frame callback fired).
    if (!_navScrollInitialized) _measureAndJumpNav();

    // Hide the scroll hint once the user starts scrolling down.
    if (_showScrollHint && currentScroll > 0) {
      setState(() => _showScrollHint = false);
    }

    // Trigger fetch when scrolled past 80%
    if (currentScroll >= maxScroll * 0.8) {
      _controller.loadMoreQuarkPhotos();
    }
  }

  @override
  Future<void> refresh() => _controller.refresh();

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Photos ─────────────────────────────────────────────────────────────────

  void _onPhotoTap(List<PhotoItem> photos, int index) {
    if (_controller.selectionMode) {
      _controller.toggleSelection(photos[index].id);
    } else {
      _openPhoto(index);
    }
  }

  Future<void> _toggleFavorite(String id) async {
    try {
      await _controller.toggleFavorite(id);
    } catch (e) {
      if (mounted) _snack(Errors.message(e, 'update the favorite'));
    }
  }

  /// Opens the photo at [index] of the grid in the image viewer.
  Future<void> _openPhoto(int index) async {
    if (_isOpeningPhoto) return;
    _isOpeningPhoto = true;
    try {
      final navigator = Navigator.of(context);
      final opened = await _controller.openPhotoAt(index);
      if (opened == null || !mounted) return;
      final (bytes, name, relPath, serial) = opened;
      final changed = await navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            bytes: bytes!,
            name: name,
            initialIndex: index,
            imageCount: _controller.photoCount,
            relPath: relPath,
            serial: serial,
            getImageCount: () async => _controller.photoCount,
            onLoadImage: _loadPhotoAt,
            onPrefetchImage: _controller.prefetchPhotoAt,
          ),
        ),
      );
      if (changed == true) await manualRefresh();
    } finally {
      _isOpeningPhoto = false;
    }
  }

  /// Loads the photo at [index] for the open viewer.
  ///
  /// A 404 is the only answer that means the photo is really gone, and it is
  /// the only one worth a full grid refetch — the grid behind the viewer is
  /// stale. Every other failure propagates so the viewer can offer a retry,
  /// and leaves the grid alone rather than paying for a refetch on one flaky
  /// request (#1708).
  Future<LoadedPhoto> _loadPhotoAt(int index) async {
    try {
      return await _controller.loadPhotoAt(index);
    } on ApiException catch (e) {
      if (e.statusCode == 404) await manualRefresh();
      rethrow;
    }
  }

  Future<void> _uploadPhotos() async {
    if (_controller.isUploading) return;
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty || !mounted) return;

      final targets = await _controller.uploadTargets();
      UploadTarget? target = targets.length == 1 ? targets.first : null;
      if (targets.length > 1) {
        if (!mounted) return;
        target = await showDeviceUploadPicker(context, targets);
        if (target == null) return;
      }
      final serial = target?.serial ?? '';

      try {
        await _controller.uploadPhotos(
          picked,
          serial: serial.isNotEmpty ? serial : null,
        );
        if (!mounted) return;
        _snack(
          'Uploaded ${picked.length == 1 ? picked.first.name : '${picked.length} photos'}',
        );
        await manualRefresh();
      } catch (e) {
        if (mounted) _snack(Errors.message(e, 'upload your photos'));
      }
    } on MissingPluginException {
      if (mounted) _snack('File picker not available. Fully restart the app.');
    }
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  /// Leaves selection mode, and the page too when it was opened to add to an
  /// album.
  void _cancelSelection() {
    final wasAdding = _controller.addingToAlbum != null;
    _controller.exitSelectionMode();
    if (wasAdding) Navigator.of(context).pop();
  }

  Future<void> _pickAlbumForSelection() async {
    final album = await AlbumPickerSheetHost.show(
      context,
      selectedCount: _controller.selectedIds.length,
      loadAlbums: _controller.fetchAlbums,
    );
    if (album == null || !mounted) return;
    await _addSelectedTo(album);
  }

  Future<void> _addSelectedTo(AlbumItem album) async {
    final wasAdding = _controller.addingToAlbum != null;
    final outcome = await _controller.addSelectedToAlbum(album.id);
    if (!mounted) return;

    final added = outcome.added;
    if (added == 0 && outcome.skipped > 0) {
      _snack('No photos added — device photos cannot be added to albums yet');
    } else if (added > 0) {
      final failed = outcome.failed > 0 ? ' (${outcome.failed} failed)' : '';
      _snack(
        '$added ${added == 1 ? 'photo' : 'photos'} added to "${album.name}"'
        '$failed',
      );
    } else {
      _snack(Errors.couldNot('add photos to "${album.name}"'));
    }

    // Stay in adding mode when nothing was added, so the user can try again.
    if (wasAdding && added > 0) Navigator.of(context).pop();
  }

  // ── Albums ─────────────────────────────────────────────────────────────────

  void _openAlbum(AlbumItem item) {
    final album = _controller.albumById(item.id);
    if (album == null) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AlbumPage(album: album)));
  }

  Future<void> _createAlbum({int? parentId}) async {
    final name = await AlbumNameDialog.show(context, title: 'New album');
    if (name == null || name.isEmpty) return;
    try {
      await _controller.createAlbum(name, parentId: parentId);
    } catch (e) {
      if (mounted) _snack(Errors.message(e, 'create the album'));
    }
  }

  Future<void> _renameAlbum(AlbumItem album) async {
    final name = await AlbumNameDialog.show(
      context,
      title: 'Rename album',
      initial: album.name,
    );
    if (name == null || name.isEmpty || name == album.name) return;
    try {
      await _controller.renameAlbum(album.id, name);
    } catch (e) {
      if (mounted) _snack(Errors.message(e, 'rename the album'));
    }
  }

  Future<void> _deleteAlbum(AlbumItem album) async {
    if (!await DeleteAlbumDialog.show(context, albumName: album.name)) return;
    try {
      await _controller.deleteAlbum(album.id);
    } catch (e) {
      if (mounted) _snack(Errors.message(e, 'delete the album'));
    }
  }

  void _showAlbumActions(AlbumItem album) {
    AlbumActionsSheet.show(
      context,
      onRename: () => _renameAlbum(album),
      onCreateSubAlbum: () => _createAlbum(parentId: album.id),
      onDelete: () => _deleteAlbum(album),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The split view owns the breakpoint. The page only asks which layout it
    // is in because the nav panel exists solely in the collapsed one, so that
    // is the only layout with anything to measure or to hint about.
    final compact = QuarkSplitView.isCollapsed(context);
    _compactLayout = compact;
    if (compact && !_navScrollInitialized) _scheduleNavMeasure();
    final contentWidth = QuarkSplitView.contentWidthOf(context);
    final columnBounds = PhotoGridConfig.columnBounds(contentWidth);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_controller.selectionMode) _cancelSelection();
        },
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final c = _controller;
            final photos = c.photos;
            final selectedIds = c.selectedIds;

            return QuarkPageScaffold(
              title: 'Photos',
              icon: QuarkIcons.photo_library_outlined,
              actions: [
                IconButton(
                  icon: c.isUploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  tooltip: 'Upload photos',
                  onPressed: c.isUploading ? null : _uploadPhotos,
                ),
                TextButton(
                  onPressed: c.enterSelectionMode,
                  child: const Text('Select'),
                ),
                RefreshIconButton(
                  isRefreshing: isRefreshing,
                  onPressed: manualRefresh,
                  tooltip: 'Reload photos',
                ),
                const AppThemeToggle(),
              ],
              appBar: c.selectionMode
                  ? PhotosSelectionAppBar(
                      selectedCount: selectedIds.length,
                      albumName: c.addingToAlbum?.name,
                      onConfirm: selectedIds.isNotEmpty
                          ? () => _addSelectedTo(c.addingToAlbum!)
                          : null,
                      onCancel: _cancelSelection,
                    )
                  : null,
              drawer: QuarkDrawer(
                activeSection: QuarkDrawerSection.photos,
                onTapFiles: () => context.go(AppRoutes.files),
                onTapPhotos: () => Navigator.of(context).pop(),
                onTapDocs: () => context.go(AppRoutes.docs),
                onTapSheets: () => context.go(AppRoutes.sheets),
                onTapDevices: () => context.go(AppRoutes.devices),
                onTapHealth: () => context.go(AppRoutes.health),
                onTapVault: () => context.go(AppRoutes.vault),
                onTapSettings: () => context.go(AppRoutes.settings),
              ),
              bottomBar: c.selectionMode && c.addingToAlbum == null
                  ? PhotoSelectionBar(
                      selectedCount: selectedIds.length,
                      onAddToAlbum: _pickAlbumForSelection,
                      onCancel: c.exitSelectionMode,
                    )
                  : null,
              body: Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: manualRefresh,
                    child: QuarkSplitView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      // The collapsed layout stacks the sidebar above the
                      // grid in the same scroll view, and the page measures
                      // it so the grid starts flush with the top.
                      collapsedSidebarKey: _navPanelKey,
                      sidebar: PhotoLibrarySidebar(
                        columns: c.columns,
                        minColumns: columnBounds.min,
                        maxColumns: columnBounds.max,
                        onColumnsChanged: c.setColumns,
                        categories: c.showsCategories
                            ? PhotoCategoryList(
                                categories: c.categories,
                                selectedId: c.selectedCategory.name,
                                expanded: c.categoriesExpanded,
                                onToggleExpanded: c.toggleCategoriesExpanded,
                                onSelected: (id) => c.selectCategory(
                                  PhotoCategory.values.byName(id),
                                ),
                              )
                            : null,
                        albums: AlbumSidebar(
                          albums: c.albums,
                          isLoading: c.albumsLoading,
                          expandedIds: c.expandedAlbumIds,
                          shrinkWrap: compact,
                          onAlbumSelected: _openAlbum,
                          onToggleExpanded: c.toggleAlbumExpanded,
                          onCreateAlbum: _createAlbum,
                          onAlbumLongPress: _showAlbumActions,
                        ),
                      ),
                      slivers: [
                        PhotoGrid(
                          photos: photos,
                          crossAxisCount: PhotoGridConfig.columnsFor(
                            contentWidth,
                            c.columns,
                          ),
                          selectedIds: selectedIds,
                          selectionMode: c.selectionMode,
                          isLoading: isInitialLoad,
                          hasMore: c.hasMore,
                          isLoadingMore: c.isLoadingMore,
                          emptyState: PhotosEmptyState(
                            unreachable: c.quarkUnreachable,
                            showingFavorites:
                                c.selectedCategory == PhotoCategory.favorites,
                            hostAddress: c.activeHost,
                            onRetry: manualRefresh,
                            onManageHosts: () => context.go(AppRoutes.settings),
                          ),
                          thumbnailBuilder: (context, photo) => PhotoThumbnail(
                            url: c.thumbnailUrl(photo.id),
                            asset: c.assetFor(photo.id),
                          ),
                          onTap: (i) => _onPhotoTap(photos, i),
                          onLongPress: (i) =>
                              c.selectFromLongPress(photos[i].id),
                          onDoubleTap: (i) => _toggleFavorite(photos[i].id),
                        ),
                      ],
                    ),
                  ),
                  // The collapsed layout starts scrolled past its nav panel,
                  // so the chevron is the only sign the panel is up there.
                  if (compact && _showScrollHint)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ScrollUpHint(),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

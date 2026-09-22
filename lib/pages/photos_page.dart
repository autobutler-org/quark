import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/photo_grid_config.dart';
import 'package:quark/utils/quark_widget_items.dart';
import 'package:quark/widgets/device_upload_picker.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/photos/add_to_album_sheet.dart';
import 'package:quark/widgets/photos/album_actions_sheet.dart';
import 'package:quark/widgets/photos/album_item_actions_sheet.dart';
import 'package:quark/widgets/photos/album_name_dialog.dart';
import 'package:quark/widgets/photos/album_picker_sheet.dart';
import 'package:quark/widgets/photos/delete_album_dialog.dart';
import 'package:quark/widgets/photos/photo_thumbnail.dart';
import 'package:quark/widgets/photos/photos_empty_state.dart';
import 'package:quark/widgets/photos/photos_selection_app_bar.dart';
import 'package:quark/widgets/photos/remove_from_album_dialog.dart';
import 'package:quark/widgets/upload_drop_zone.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

class PhotosPage extends StatefulWidget {
  const PhotosPage({this.album, super.key});

  /// The `?album=` query naming the album the grid shows — a name path or an
  /// id, see `resolveAlbumLink` — or null for All photos. Albums open in
  /// place rather than on a page of their own (#1916).
  final String? album;

  @override
  State<PhotosPage> createState() => PhotosPageState();
}

class PhotosPageState extends State<PhotosPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  /// Whether this page shows Demo mode's sample library (#1746). Read once:
  /// Settings is its own route, so flipping the switch there builds a fresh
  /// page on the way back.
  final bool _demo = AppSettings.instance.demoMode.value;

  late final PhotosController _controller = _demo
      ? PhotosController.demo()
      : PhotosController();

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
  StreamSubscription<FileEvent>? _eventSub;
  StreamSubscription<void>? _reconnectSub;

  @override
  void initState() {
    super.initState();
    EventsService.instance.start();
    // A sharing change, or a change to one of this account's groups, decides
    // which photos it can see.
    _eventSub = EventsService.instance.events.listen((evt) {
      if (evt.kind == 'access_changed') manualRefresh();
    });
    // Whatever changed while the socket was down sent no event we saw.
    _reconnectSub = EventsService.instance.reconnects.listen(
      (_) => manualRefresh(),
    );
    _scrollController.addListener(_onScroll);
    _scheduleNavMeasure();
    _controller.addListener(_scheduleAlbumUrlSync);
    _controller.showAlbumLink(widget.album);
  }

  /// go_router keeps this State when only the query changes, so a new
  /// `?album=` arrives here.
  @override
  void didUpdateWidget(PhotosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.album != oldWidget.album) {
      _controller.showAlbumLink(widget.album);
      // Another spelling of the album already showing changes nothing in the
      // controller, so nothing else would rewrite it.
      _scheduleAlbumUrlSync();
    }
  }

  bool _albumUrlSyncScheduled = false;

  /// Points the URL at [PhotosController.albumLink] after the frame, once
  /// the controller has changed: a link by id or in another case resolving,
  /// the add-photos round trip leaving and returning to the album, and the
  /// showing album being renamed or deleted. Deferred because the controller
  /// also changes while go_router is building this page.
  void _scheduleAlbumUrlSync() {
    if (_albumUrlSyncScheduled) return;
    _albumUrlSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _albumUrlSyncScheduled = false;
      if (!mounted) return;
      final link = _controller.albumLink;
      // The same value is already the location, so writing it is skipped.
      if (link != widget.album) context.go(AppRoutes.photosAlbum(link));
    });
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
    _eventSub?.cancel();
    _reconnectSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.removeListener(_scheduleAlbumUrlSync);
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
      final album = _controller.selectedAlbum;
      final opened = await _controller.openPhotoAt(index);
      if (opened == null || !mounted) return;
      final (bytes, name, relPath, serial) = _forViewer(opened);
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
            // Only a user album offers "remove from this album" in the viewer;
            // the Quark fills system albums itself (#992).
            sourceAlbum: _demo || (album?.isSystemAlbum ?? true) ? null : album,
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
      return _forViewer(await _controller.loadPhotoAt(index));
    } on ApiException catch (e) {
      if (e.statusCode == 404) await manualRefresh();
      rethrow;
    }
  }

  /// A sample photo has no Quark path, so the viewer gets none and keeps its
  /// metadata, rotate, delete, and album actions off.
  LoadedPhoto _forViewer(LoadedPhoto photo) {
    final (bytes, name, _, _) = photo;
    return _demo ? (bytes, name, null, null) : photo;
  }

  Future<void> _uploadPhotos() async {
    if (_controller.isUploading) return;
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty || !mounted) return;

      final serial = await _pickUploadSerial();
      if (serial == null) return;
      // A user album showing takes the upload too (#2240). System albums and
      // Favorites are filled by the Quark or by starring, so those stay a
      // plain library upload.
      final showing = _controller.selectedAlbum;
      final album = showing == null || showing.isSystemAlbum ? null : showing;

      try {
        final outcome = await _controller.uploadPhotos(
          picked,
          serial: serial.isNotEmpty ? serial : null,
          albumId: album?.id,
        );
        if (!mounted) return;
        final uploaded =
            'Uploaded ${picked.length == 1 ? picked.first.name : '${picked.length} photos'}';
        if (outcome == null || album == null) {
          _snack(uploaded);
        } else if (outcome.failed == 0) {
          _snack('$uploaded to "${album.name}"');
        } else {
          final which = outcome.failed < picked.length
              ? '${outcome.failed} of them'
              : picked.length == 1
              ? 'it'
              : 'them';
          _snack(
            '$uploaded. '
            '${Errors.message(outcome.error, 'add $which to "${album.name}"')}',
          );
        }
        await manualRefresh();
      } catch (e) {
        if (mounted) _snack(Errors.message(e, 'upload your photos'));
      }
    } on MissingPluginException {
      if (mounted) _snack('File picker not available. Fully restart the app.');
    }
  }

  /// Uploads the photos among files dragged onto the page, the same way the
  /// upload button does, and says so when something dropped is not a photo
  /// rather than dropping it silently (#2214).
  Future<void> _uploadDroppedFiles(List<DropItem> items) async {
    if (_controller.isUploading) return;
    final (:photos, :notPhotos) = _controller.sortDroppedFiles(items);
    if (photos.isEmpty) {
      if (notPhotos > 0) _snack(Errors.notPhotos(notPhotos));
      return;
    }

    final serial = await _pickUploadSerial();
    if (serial == null || !mounted) return;

    try {
      final uploaded = await _controller.uploadDroppedPhotos(
        photos,
        serial: serial.isNotEmpty ? serial : null,
      );
      if (!mounted) return;
      final skipped = notPhotos > 0 ? ' ${Errors.notPhotos(notPhotos)}' : '';
      _snack(
        'Uploaded ${uploaded == 1 ? '1 photo' : '$uploaded photos'}.$skipped',
      );
      await manualRefresh();
    } catch (e) {
      if (mounted) _snack(Errors.message(e, 'upload your photos'));
    }
  }

  /// The serial of the device an upload goes to — `''` for the default
  /// device — or null when the user dismissed the device picker.
  Future<String?> _pickUploadSerial() async {
    final targets = await _controller.uploadTargets();
    UploadTarget? target = targets.length == 1 ? targets.first : null;
    if (targets.length > 1) {
      if (!mounted) return null;
      target = await showDeviceUploadPicker(context, targets);
      if (target == null) return null;
    }
    return target?.serial ?? '';
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  Future<void> _pickAlbumForSelection() async {
    final album = await AlbumPickerSheetHost.show(
      context,
      selectedCount: _controller.selectedIds.length,
      loadAlbums: _controller.fetchAlbums,
      // A household with no albums yet is exactly the one adding photos to
      // its first (#2041), so the sheet can make it rather than sending them
      // away to do it.
      onCreateAlbum: _createAlbumForSelection,
    );
    if (album == null || !mounted) return;
    await _addSelectedTo(album);
  }

  /// Names and creates an album from inside the picker, for a Quark with none
  /// yet. Answers with it so the picker can hand it straight back (#2041).
  Future<AlbumItem?> _createAlbumForSelection() async {
    final name = await AlbumNameDialog.show(
      context,
      title: 'New album',
      isNameTaken: (name) => _controller.albumNameTaken(name),
    );
    if (name == null || name.isEmpty) return null;
    try {
      return await _controller.createAlbum(name);
    } catch (e) {
      if (mounted) _snack(Errors.album(e, 'create the album'));
      return null;
    }
  }

  Future<void> _addSelectedTo(AlbumItem album) async {
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
      _snack(Errors.message(outcome.error, 'add photos to "${album.name}"'));
    }
  }

  // ── Albums ─────────────────────────────────────────────────────────────────

  /// Shows the album [id] in place, or All photos for null, at its canonical
  /// link. [didUpdateWidget] hands the new URL to the controller.
  void _showAlbum(int? id) {
    context.go(
      AppRoutes.photosAlbum(id == null ? null : _controller.albumLinkFor(id)),
    );
    _scrollToGrid();
  }

  /// The collapsed layout stacks the sidebar above the grid, so a tap on a
  /// sidebar row would change a grid scrolled out of sight. Bring it back.
  void _scrollToGrid() {
    if (!_compactLayout || !_scrollController.hasClients) return;
    final box = _navPanelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _scrollController.animateTo(
      box.size.height,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Switches to All photos to pick photos for [album], and back to the album
  /// once they are added or the selection is canceled.
  void _addPhotosTo(AlbumItem album) {
    _controller.enterSelectionMode(addingTo: album);
    _showAlbum(null);
  }

  /// What a long press does while an album shows: that photo's menu.
  /// Selection stays a library feature. Demo albums refuse edits, so they
  /// get no menu, as before.
  void _showAlbumItemActions(PhotoAlbum album, String id) {
    final path = _controller.quarkPathOf(id);
    if (_demo || path == null) return;
    AlbumItemActionsSheet.show(
      context,
      onAddToAnotherAlbum: () => AddToAlbumSheetHost.show(
        context,
        deviceSerial: path.serial,
        relPath: path.relPath,
      ),
      onRemoveFromFavorites: album.isFavorites
          ? () => _toggleFavorite(id)
          : null,
      onRemoveFromAlbum: album.isSystemAlbum
          ? null
          : () => _removeFromAlbum(id),
    );
  }

  Future<void> _removeFromAlbum(String id) async {
    if (!await RemoveFromAlbumDialog.show(context)) return;
    try {
      await _controller.removeFromSelectedAlbum(id);
    } catch (e) {
      if (mounted) _snack(Errors.message(e, 'remove the photo from the album'));
    }
  }

  Future<void> _createAlbum({int? parentId}) async {
    final name = await AlbumNameDialog.show(
      context,
      title: 'New album',
      isNameTaken: (name) =>
          _controller.albumNameTaken(name, parentId: parentId),
    );
    if (name == null || name.isEmpty) return;
    try {
      await _controller.createAlbum(name, parentId: parentId);
    } catch (e) {
      if (mounted) _snack(Errors.album(e, 'create the album'));
    }
  }

  Future<void> _renameAlbum(AlbumItem album) async {
    final name = await AlbumNameDialog.show(
      context,
      title: 'Rename album',
      initial: album.name,
      isNameTaken: (name) => _controller.albumNameTaken(
        name,
        parentId: album.parentId,
        except: album.id,
      ),
    );
    if (name == null || name.isEmpty || name == album.name) return;
    try {
      await _controller.renameAlbum(album.id, name);
    } catch (e) {
      if (mounted) _snack(Errors.album(e, 'rename the album'));
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
          if (_controller.selectionMode) _controller.exitSelectionMode();
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
            final album = c.selectedAlbum;
            final albumError = c.albumError;

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
                if (album == null)
                  TextButton(
                    onPressed: c.enterSelectionMode,
                    child: const Text('Select'),
                  ),
                // The Quark fills system albums itself and refuses edits (#992).
                // An empty album carries this button in its empty state
                // instead, so the page never shows two.
                if (album != null && !album.isSystemAlbum && photos.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('photos_add_to_album'),
                    onPressed: () => _addPhotosTo(album.toAlbumItem()),
                    icon: const Icon(QuarkIcons.add_rounded, size: 18),
                    label: const Text('Add Photos'),
                  ),
                const AppThemeToggle(),
              ],
              onRefresh: manualRefresh,
              isRefreshing: isRefreshing,
              appBar: c.selectionMode
                  ? PhotosSelectionAppBar(
                      selectedCount: selectedIds.length,
                      albumName: c.addingToAlbum?.name,
                      onConfirm: selectedIds.isNotEmpty
                          ? () => _addSelectedTo(c.addingToAlbum!)
                          : null,
                      onCancel: c.exitSelectionMode,
                    )
                  : null,
              drawer: const AppDrawer(activeSection: QuarkDrawerSection.photos),
              bottomBar: c.selectionMode && c.addingToAlbum == null
                  ? PhotoSelectionBar(
                      selectedCount: selectedIds.length,
                      onAddToAlbum: _pickAlbumForSelection,
                      onCancel: c.exitSelectionMode,
                    )
                  : null,
              body: UploadDropZone(
                enabled: !c.isUploading,
                onDrop: _uploadDroppedFiles,
                child: Stack(
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
                            selectedAlbumId: c.selectedAlbumId,
                            onAllPhotosSelected: () => _showAlbum(null),
                            onAlbumSelected: (item) => _showAlbum(item.id),
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
                            isLoading: isInitialLoad || c.albumLoading,
                            // Unreachable has its own view in the empty state.
                            error: albumError == null || c.quarkUnreachable
                                ? null
                                : Errors.message(albumError, 'load the album'),
                            hasMore: c.hasMore,
                            isLoadingMore: c.isLoadingMore,
                            emptyState: PhotosEmptyState(
                              unreachable: c.quarkUnreachable,
                              showingFavorites: album == null
                                  ? c.selectedCategory ==
                                        PhotoCategory.favorites
                                  : album.isFavorites,
                              albumName: album?.name,
                              hostAddress: c.activeHost,
                              onRetry: manualRefresh,
                              onManageHosts: () =>
                                  context.go(AppRoutes.settings),
                              onUploadPhotos: c.isUploading
                                  ? null
                                  : _uploadPhotos,
                              // Same action as the app bar's Add Photos, and
                              // absent for the same albums (#992).
                              onAddPhotosToAlbum:
                                  album != null && !album.isSystemAlbum
                                  ? () => _addPhotosTo(album.toAlbumItem())
                                  : null,
                            ),
                            thumbnailBuilder: (context, photo) =>
                                PhotoThumbnail(
                                  url: c.thumbnailUrl(photo.id),
                                  asset: c.assetFor(photo.id),
                                ),
                            onTap: (i) => _onPhotoTap(photos, i),
                            onLongPress: (i) => album == null
                                ? c.selectFromLongPress(photos[i].id)
                                : _showAlbumItemActions(album, photos[i].id),
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
              ),
            );
          },
        ),
      ),
    );
  }
}

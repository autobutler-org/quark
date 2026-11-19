import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/controllers/sidebar_controller.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/slideshow_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/clipboard_utils.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_viewer_actions.dart'
    show downloadViewedPhotoAsJpeg;
import 'package:quark/services/client_thumbnails.dart'
    show canConvertImageToJpeg;
import 'package:quark/services/photo_jpeg_download.dart'
    show offersJpegDownload;
import 'package:quark/utils/overlay_history.dart';
import 'package:quark/utils/photo_grid_config.dart';
import 'package:quark/utils/trash_config.dart';
import 'package:quark/utils/quark_widget_items.dart';
import 'package:quark/widgets/device_upload_picker.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/photos/add_to_album_sheet.dart';
import 'package:quark/widgets/photos/album_actions_menu.dart';
import 'package:quark/widgets/photos/export/export_photos_dialog.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/widgets/sharing/show_share_sheet.dart';
import 'package:quark/widgets/photos/library_photo_menu.dart';
import 'package:quark/widgets/photos/album_item_menu.dart';
import 'package:quark/widgets/photos/album_name_dialog.dart';
import 'package:quark/widgets/photos/album_picker_sheet.dart';
import 'package:quark/widgets/photos/delete_album_dialog.dart';
import 'package:quark/widgets/photos/photo_library_nav.dart';
import 'package:quark/widgets/photos/photo_library_sheet.dart';
import 'package:quark/widgets/photos/photo_sort_button.dart';
import 'package:quark/widgets/photos/photo_thumbnail.dart';
import 'package:quark/widgets/photos/photos_bar_bottom.dart';
import 'package:quark/widgets/photos/photos_empty_state.dart';
import 'package:quark/widgets/photos/photos_search_bar.dart';
import 'package:quark/widgets/photos/remove_from_album_dialog.dart';
import 'package:quark/widgets/upload_drop_zone.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Photos page: the photo library as a grid, filtered by album and by a
/// search for a file name, with upload.
class PhotosPage extends StatefulWidget {
  const PhotosPage({
    this.album,
    this.controller,
    this.playVideo = ImageViewerPage.pushVideoPlayer,
    super.key,
  });

  /// Plays a video tapped in the grid or reached in the viewer (#3428); by
  /// default, pushes the video player. A test passes a recorder.
  final Future<void> Function(BuildContext context, Uri url, String name)
  playVideo;

  /// A controller to show instead of the page's own, so a test can count the
  /// refreshes it asks for. The page disposes it either way.
  @visibleForTesting
  final PhotosController? controller;

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

  late final PhotosController _controller =
      widget.controller ??
      (_demo ? PhotosController.demo() : PhotosController());

  /// Guards [_openPhoto], so a second tap while the bytes are still
  /// downloading cannot push a second viewer.
  bool _isOpeningPhoto = false;

  /// Whether the search strip is showing (#2059). Closing it ends the search.
  bool _searchOpen = false;

  final ScrollController _scrollController = ScrollController();

  /// The wide layout's library sidebar, kept per device (#4294).
  final _libraryPane = SidebarController(
    'photos_library',
    defaultWidth: QuarkSplitView.defaultSidebarWidth,
  );

  /// Whether a phone's upload button shows: it fades while the grid scrolls
  /// down and comes back on the way up (#4150).
  bool _fabVisible = true;
  double _lastScrollOffset = 0;
  StreamSubscription<void>? _eventSub;

  @override
  void initState() {
    super.initState();
    EventsService.instance.start();
    // A photo deleted, moved or uploaded anywhere, the duplicates view
    // underneath this page included, or a sharing change. This page's own
    // upload reloads once it finishes. A reconnect arrives as a resync, so it
    // needs no listener of its own. A burst of them, from a conversion job, a
    // restore or a dropped socket, reloads once rather than once per event
    // (#3448).
    _eventSub = EventsService.instance.listingChanges.listen((_) {
      // An upload and an action on the selection each reload once when they
      // finish, rather than once per photo they changed (#4154).
      if (!_controller.isUploading && !_controller.isActingOnSelection) {
        manualRefresh();
      }
    });
    _scrollController.addListener(_onScroll);
    _libraryPane.addListener(_onLibraryPaneChanged);
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

  @override
  void dispose() {
    _eventSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _libraryPane.dispose();
    _controller.removeListener(_scheduleAlbumUrlSync);
    _controller.dispose();
    super.dispose();
  }

  /// Rebuilds for a resized or hidden sidebar, which moves the grid's
  /// column count.
  void _onLibraryPaneChanged() => setState(() {});

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final currentScroll = _scrollController.position.pixels;
    final maxScroll = _scrollController.position.maxScrollExtent;

    final fabVisible = QuarkCreateFab.visibleAfterScroll(
      offset: currentScroll,
      delta: currentScroll - _lastScrollOffset,
      visible: _fabVisible,
    );
    _lastScrollOffset = currentScroll;
    if (fabVisible != _fabVisible) setState(() => _fabVisible = fabVisible);

    // Trigger fetch when scrolled past 80%
    if (currentScroll >= maxScroll * 0.8) {
      _controller.loadMoreQuarkPhotos();
    }
  }

  @override
  Future<void> refresh() => _controller.refresh();

  void _toggleSearch() {
    setState(() => _searchOpen = !_searchOpen);
    if (!_searchOpen) _controller.setSearchQuery('');
  }

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
      if (mounted) {
        showMessage(context, Errors.message(e, 'update the favorite'));
      }
    }
  }

  /// Opens the photo at [index] of the grid in the image viewer, or a video
  /// in the video player, streamed rather than downloaded (#3428).
  Future<void> _openPhoto(int index) async {
    if (_isOpeningPhoto) return;
    final video = _controller.videoAt(index);
    if (video != null) {
      await widget.playVideo(context, video.url, video.name);
      return;
    }
    _isOpeningPhoto = true;
    try {
      final album = _controller.selectedAlbum;
      final opened = await _controller.openPhotoAt(index);
      if (opened == null || !mounted) return;
      final (bytes, name, relPath, serial) = _forViewer(opened);
      final changed = await pushWithBrowserBack<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            bytes: bytes!,
            name: name,
            initialIndex: index,
            imageCount: _controller.photoCount,
            // The whole library, not the pages loaded so far (#3357).
            totalCount: _controller.photoTotal,
            onLoadMore: _controller.loadMoreQuarkPhotos,
            relPath: relPath,
            serial: serial,
            getImageCount: () async => _controller.photoCount,
            onLoadImage: _loadPhotoAt,
            onPrefetchImage: _controller.prefetchPhotoAt,
            // Videos sit in the grid too, so a swipe reaches them (#3428).
            videoAt: _controller.videoAt,
            playVideo: widget.playVideo,
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

  /// Uploads after asking which device to write to (#3194).
  Future<void> _uploadToDevice() => _uploadPhotos(chooseDevice: true);

  Future<void> _uploadPhotos({bool chooseDevice = false}) async {
    if (_controller.isUploading) return;
    try {
      final picked = await FilePicker.pickFiles(type: FileType.media);
      if (picked.isEmpty || !mounted) return;

      // A user album showing takes the upload too (#2240). System albums and
      // Favorites are filled by the Quark or by starring, so those stay a
      // plain library upload.
      final showing = _controller.selectedAlbum;
      final album = showing == null || showing.isSystemAlbum ? null : showing;

      try {
        final serial = await _uploadSerial(chooseDevice: chooseDevice);
        if (serial == null) return;
        final outcome = await _controller.uploadPhotos(
          picked,
          serial: serial.isNotEmpty ? serial : null,
          albumId: album?.id,
        );
        if (!mounted) return;
        final uploaded =
            'Uploaded ${picked.length == 1 ? picked.first.name : '${picked.length} photos'}';
        if (outcome == null || album == null) {
          showMessage(context, uploaded);
        } else if (outcome.failed == 0) {
          showMessage(context, '$uploaded to "${album.name}"');
        } else {
          final which = outcome.failed < picked.length
              ? '${outcome.failed} of them'
              : picked.length == 1
              ? 'it'
              : 'them';
          showMessage(
            context,
            '$uploaded. '
            '${Errors.message(outcome.error, 'add $which to "${album.name}"')}',
          );
        }
        await manualRefresh();
      } catch (e) {
        if (mounted) {
          showMessage(context, Errors.message(e, 'upload your photos'));
        }
      }
    } on MissingPluginException {
      if (mounted) {
        showMessage(
          context,
          'File picker not available. Fully restart the app.',
        );
      }
    }
  }

  /// Uploads the photos among files dragged onto the page, the same way the
  /// upload button does, and says so when something dropped is not a photo
  /// rather than dropping it silently (#2214).
  Future<void> _uploadDroppedFiles(List<DropItem> items) async {
    if (_controller.isUploading) return;
    final (:photos, :notPhotos) = _controller.sortDroppedFiles(items);
    if (photos.isEmpty) {
      if (notPhotos > 0) showMessage(context, Errors.notPhotos(notPhotos));
      return;
    }

    try {
      final serial = await _uploadSerial();
      if (serial == null || !mounted) return;
      final uploaded = await _controller.uploadDroppedPhotos(
        photos,
        serial: serial.isNotEmpty ? serial : null,
      );
      if (!mounted) return;
      final skipped = notPhotos > 0 ? ' ${Errors.notPhotos(notPhotos)}' : '';
      showMessage(
        context,
        'Uploaded ${uploaded == 1 ? '1 photo' : '$uploaded photos'}.$skipped',
      );
      await manualRefresh();
    } catch (e) {
      if (mounted) {
        showMessage(context, Errors.message(e, 'upload your photos'));
      }
    }
  }

  /// The serial of the device an upload goes to — `''` for built-in
  /// storage — or null when the user dismissed the device picker.
  /// [chooseDevice] asks even when there is a default (#3194). Throws when
  /// the devices cannot be listed (#3192).
  Future<String?> _uploadSerial({bool chooseDevice = false}) =>
      _controller.uploadSerial(
        chooseDevice: chooseDevice,
        pick: (targets, initial, notice) async => mounted
            ? showDeviceUploadPicker(
                context,
                targets,
                initial: initial,
                notice: notice,
              )
            : null,
      );

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
      if (mounted) showMessage(context, Errors.album(e, 'create the album'));
      return null;
    }
  }

  Future<void> _addSelectedTo(AlbumItem album) async {
    final outcome = await _controller.addSelectedToAlbum(album.id);
    if (!mounted) return;

    final added = outcome.added;
    if (added == 0 && outcome.skipped > 0) {
      showMessage(
        context,
        'No photos added — device photos cannot be added to albums yet',
      );
    } else if (added == 0 && outcome.alreadyIn > 0 && outcome.failed == 0) {
      // Nothing changed, so nothing was added (#3361).
      showMessage(
        context,
        outcome.alreadyIn == 1
            ? 'Already in "${album.name}"'
            : '${outcome.alreadyIn} photos already in "${album.name}"',
      );
    } else if (added > 0) {
      final notes = [
        if (outcome.alreadyIn > 0) '${outcome.alreadyIn} already in it',
        if (outcome.failed > 0) '${outcome.failed} failed',
      ];
      showMessage(
        context,
        '$added ${added == 1 ? 'photo' : 'photos'} added to "${album.name}"'
        '${notes.isEmpty ? '' : ' (${notes.join(', ')})'}',
      );
    } else {
      showMessage(
        context,
        Errors.message(outcome.error, 'add photos to "${album.name}"'),
      );
    }
  }

  /// Says how an action on the selection went when any of it failed; the
  /// photos that failed stay selected for another try (#4154).
  void _reportSelection(
    SelectionOutcome outcome,
    String Function(String photos) action,
  ) {
    if (!mounted || outcome.failed == 0) return;
    showMessage(
      context,
      Errors.selection(
        outcome.error,
        action,
        failed: outcome.failed,
        total: outcome.total,
      ),
    );
  }

  /// Favorites the selection, or takes it out of Favorites when every photo already is
  /// one; [favorite] false always takes it out, for Remove from favorites.
  Future<void> _favoriteSelection({bool? favorite}) async {
    final want = favorite ?? !_controller.selectionAllFavorites;
    final outcome = await _controller.favoriteSelected(favorite: want);
    _reportSelection(
      outcome,
      (photos) => want ? 'favorite $photos' : 'unfavorite $photos',
    );
  }

  Future<void> _downloadSelection() async => _reportSelection(
    await _controller.downloadSelected(),
    (photos) => 'download $photos',
  );

  Future<void> _copySelection() async {
    final outcome = await _controller.copySelected();
    if (!mounted) return;
    if (outcome.failed == 0 && outcome.done > 0) {
      showMessage(
        context,
        outcome.done == 1 ? 'Made 1 copy' : 'Made ${outcome.done} copies',
      );
    }
    _reportSelection(outcome, (photos) => 'copy $photos');
  }

  Future<void> _deleteSelection() async {
    final count = _controller.selectedIds.length;
    final one = count == 1;
    final confirmed = await confirmAction(
      context,
      title: one
          ? 'Move 1 photo to the trash?'
          : 'Move $count photos to the trash?',
      message:
          'You can restore ${one ? 'it' : 'them'} from the trash for '
          '${TrashConfig.retentionDays} days.',
      confirmLabel: 'Move to Trash',
      keyPrefix: 'photo_selection_delete',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    _reportSelection(
      await _controller.deleteSelected(),
      (photos) => 'move $photos to the trash',
    );
  }

  Future<void> _removeSelectionFromAlbum() async {
    final count = _controller.selectedIds.length;
    final one = count == 1;
    final confirmed = await confirmAction(
      context,
      title: one
          ? 'Remove 1 photo from the album?'
          : 'Remove $count photos from the album?',
      message:
          'This removes ${one ? 'the photo' : 'them'} from this album. The '
          'files on disk are not affected.',
      confirmLabel: 'Remove',
      keyPrefix: 'photo_selection_remove',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    _reportSelection(
      await _controller.removeSelectedFromAlbum(),
      (photos) => 'remove $photos from the album',
    );
  }

  /// The share sheet for the one photo selected; the sheet shares one path.
  void _shareSelection() {
    final id = _controller.selectedIds.single;
    final path = _controller.quarkPathOf(id);
    if (path == null) return;
    showShareSheet(
      context,
      deviceSerial: path.serial,
      relPath: path.relPath,
      name: path.relPath.split('/').last,
    );
  }

  /// Shows the album [id] in place, or All photos for null, at its canonical
  /// link. [didUpdateWidget] hands the new URL to the controller.
  void _showAlbum(int? id) {
    context.go(
      AppRoutes.photosAlbum(id == null ? null : _controller.albumLinkFor(id)),
    );
  }

  /// The library picker a phone shows in place of the sidebar (#4149). A
  /// pick starts the grid from its top, since the grid now shows another
  /// album or category.
  void _openLibraryPicker() {
    PhotoLibrarySheet.show(
      context,
      controller: _controller,
      onShowAlbum: (id) {
        _showAlbum(id);
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      },
      onCreateAlbum: _createAlbum,
      onAlbumMenu: _showAlbumActions,
    );
  }

  /// The grid-size slider a phone shows in a sheet from the Tools menu,
  /// rather than above the grid (#4149).
  void _openGridSize() {
    showQuarkSheet<void>(
      context,
      title: 'Grid size',
      builder: (sheetContext) => ListenableBuilder(
        listenable: _controller,
        builder: (sheetContext, _) {
          final bounds = PhotoGridConfig.columnBounds(
            QuarkSplitView.contentWidthOf(sheetContext),
          );
          return PhotoColumnsSlider(
            columns: _controller.columns,
            minColumns: bounds.min,
            maxColumns: bounds.max,
            onColumnsChanged: _controller.setColumns,
          );
        },
      ),
    );
  }

  /// Switches to All photos to pick photos for [album], and back to the album
  /// once they are added or the selection is canceled.
  void _addPhotosTo(AlbumItem album) {
    _controller.enterSelectionMode(addingTo: album);
    _showAlbum(null);
  }

  /// A photo's menu while an album shows, opened at [position] by the tile's
  /// button, a right-click or a long press. Selection stays a library
  /// feature. Demo albums refuse edits, so they get no menu, as before.
  void _showAlbumItemActions(PhotoAlbum album, String id, Offset position) {
    final path = _controller.quarkPathOf(id);
    if (_demo || path == null) return;
    AlbumItemMenu(
      onAddToAnotherAlbum: () => _showAddToAlbumSheet(path),
      onRemoveFromFavorites: album.isFavorites
          ? () => _toggleFavorite(id)
          : null,
      onRemoveFromAlbum: album.isSystemAlbum
          ? null
          : () => _removeFromAlbum(id),
    ).showAt(context, position);
  }

  /// A Quark photo's menu in the library, opened at [position] by the tile's
  /// button or a right-click (#2276).
  void _showLibraryPhotoActions(PhotoItem photo, Offset position) {
    final path = _controller.quarkPathOf(photo.id);
    if (path == null) return;
    LibraryPhotoMenu(
      isFavorite: photo.isFavorite,
      onAddToAlbum: () => _showAddToAlbumSheet(path),
      onToggleFavorite: () => _toggleFavorite(photo.id),
      onDownload: () => _downloadPhoto(photo.id),
      onShare: () => showShareSheet(
        context,
        deviceSerial: path.serial,
        relPath: path.relPath,
        name: photo.name,
      ),
      // A video is no picture for the clipboard, and duplicating is a
      // photo's (#3428).
      onCopy: photo.isVideo ? null : () => _copyToClipboard(photo.id),
      copyUnavailableReason: imageClipboardUnavailableReason,
      onDuplicate: photo.isVideo ? null : () => _duplicatePhoto(photo.id),
      onDelete: () => _deletePhoto(photo),
      onDownloadAsJpeg: canConvertImageToJpeg && offersJpegDownload(photo.name)
          ? () => downloadViewedPhotoAsJpeg(
              context,
              path: path.relPath,
              serial: path.serial.isEmpty ? null : path.serial,
              name: photo.name,
            )
          : null,
    ).showAt(context, position);
  }

  /// The add-to-album sheet for the photo at [path], then the tree and the
  /// showing album reloaded when the sheet changed any album, so the
  /// sidebar's counts follow without a reload (#3361).
  Future<void> _showAddToAlbumSheet(
    ({String serial, String relPath}) path,
  ) async {
    final changed = await AddToAlbumSheetHost.show(
      context,
      deviceSerial: path.serial,
      relPath: path.relPath,
    );
    if (changed && mounted) await _controller.albumsChanged();
  }

  Future<void> _downloadPhoto(String id) async {
    try {
      await _controller.downloadPhoto(id);
    } catch (e) {
      if (mounted) {
        showMessage(context, Errors.message(e, 'download the photo'));
      }
    }
  }

  /// Copies the Quark photo [id] to the system clipboard (#3436).
  Future<void> _copyToClipboard(String id) =>
      copyPhotoToClipboard(context, () => _controller.photoBytes(id));

  /// Ctrl/Cmd+C in the library: copies the one selected photo (#3436).
  void _copySelectedToClipboard() {
    final selected = _controller.selectedIds;
    if (selected.length != 1) return;
    final id = selected.single;
    if (_controller.quarkPathOf(id) == null) return;
    _copyToClipboard(id);
  }

  Future<void> _duplicatePhoto(String id) async {
    try {
      final name = await _controller.copyPhoto(id);
      if (mounted && name != null) showMessage(context, 'Copy saved as $name');
    } catch (e) {
      if (mounted) showMessage(context, Errors.message(e, 'copy the photo'));
    }
  }

  Future<void> _deletePhoto(PhotoItem photo) async {
    // The same confirmation Files and the image viewer use.
    final confirmed = await confirmDelete(context, '"${photo.name}"');
    if (confirmed != true || !mounted) return;
    try {
      await _controller.deletePhoto(photo.id);
    } catch (e) {
      if (mounted) showMessage(context, Errors.message(e, 'delete the photo'));
    }
  }

  Future<void> _removeFromAlbum(String id) async {
    if (!await RemoveFromAlbumDialog.show(context)) return;
    try {
      await _controller.removeFromSelectedAlbum(id);
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          Errors.message(e, 'remove the photo from the album'),
        );
      }
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
      if (mounted) showMessage(context, Errors.album(e, 'create the album'));
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
      if (mounted) showMessage(context, Errors.album(e, 'rename the album'));
    }
  }

  Future<void> _deleteAlbum(AlbumItem album) async {
    if (!await DeleteAlbumDialog.show(context, albumName: album.name)) return;
    try {
      await _controller.deleteAlbum(album.id);
    } catch (e) {
      if (mounted) showMessage(context, Errors.message(e, 'delete the album'));
    }
  }

  void _showAlbumActions(AlbumItem album, Offset position) {
    AlbumActionsMenu(
      onRename: () => _renameAlbum(album),
      onCreateSubAlbum: () => _createAlbum(parentId: album.id),
      onExport: () => _exportPhotos(albumId: album.id),
      onDelete: () => _deleteAlbum(album),
    ).showAt(context, position);
  }

  /// Copies albums or the library out as plain files (#3501). [albumId]
  /// starts on that album; without one, the user album showing, else the
  /// whole library.
  Future<void> _exportPhotos({int? albumId}) {
    final showing = _controller.selectedAlbum;
    final start =
        albumId ??
        (showing == null || showing.isSystemAlbum ? null : showing.id);
    return ExportPhotosDialog.show(
      context,
      albums: _controller.albums,
      initialAlbumIds: {?start},
      library: start == null,
      onOpenJobs: () => context.go(AppRoutes.systemTab(SystemTab.jobs)),
    );
  }

  /// Plays the selection, or else the photos the grid shows, full screen
  /// (#4179).
  Future<void> _playSlideshow() =>
      SlideshowPage.open(context, photos: _controller.slideshowPhotos);

  @override
  Widget build(BuildContext context) {
    // The split view owns the breakpoint. The page asks which layout it is
    // in because a phone shows the library picker and Grid size in the bar
    // instead of a sidebar above the grid (#4149).
    final compact = QuarkSplitView.isCollapsed(context);
    // Narrower still, a phone's bar is compact: two actions, and Upload
    // moves to a + button in the corner (#4150).
    final phone = QuarkAppBar.isCompact(context);
    final contentWidth = QuarkSplitView.contentWidthOf(
      context,
      sidebarWidth: _libraryPane.width,
      isSidebarCollapsed: _libraryPane.isCollapsed,
    );
    final columnBounds = PhotoGridConfig.columnBounds(contentWidth);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _copySelectedToClipboard,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            _copySelectedToClipboard,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_controller.selectionMode) {
            _controller.exitSelectionMode();
          } else if (_searchOpen) {
            _toggleSearch();
          }
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
            final searchError = c.searchError;
            final showingFavorites = album == null
                ? c.selectedCategory == PhotoCategory.favorites
                : album.isFavorites;

            // Upload and Search live in the second row, beside Tools, so a
            // tablet's top bar keeps room for the page name. Pages without
            // that row carry them in the top bar. The library has the row at
            // every width; a phone has it everywhere, since its title is the
            // way to the albums (#4149).
            final secondRow = (album == null && !_demo) || compact;
            final upload = QuarkBarSplitChip(
              key: const ValueKey('photos_upload'),
              icon: QuarkIcons.upload_rounded,
              label: c.isUploading ? 'Uploading...' : 'Upload',
              onPressed: c.isUploading ? null : _uploadPhotos,
              onSecondaryPressed: c.canChooseUploadDevice
                  ? _uploadToDevice
                  : null,
            );
            final search = QuarkBarIconButton(
              key: const ValueKey('photos_search'),
              icon: QuarkIcons.search,
              tooltip: 'Search',
              selected: _searchOpen,
              onPressed: _toggleSearch,
            );
            final select = QuarkBarIconButton(
              key: const ValueKey('photos_select'),
              icon: QuarkIcons.check_circle_outline,
              tooltip: 'Select',
              onPressed: c.enterSelectionMode,
            );
            // An album selects too, to act on its photos (#4154), but Demo
            // mode's sample albums refuse edits.
            final albumSelect = album != null && !_demo && photos.isNotEmpty
                ? select
                : null;
            // The library selects; an album adds photos as well. The Quark
            // fills system albums itself and refuses edits (#992), and an
            // empty album carries the button in its empty state, so the
            // page never shows two.
            final selectOrAdd = album == null
                ? select
                : !album.isSystemAlbum && photos.isNotEmpty
                ? QuarkBarChip(
                    key: const ValueKey('photos_add_to_album'),
                    icon: QuarkIcons.add,
                    label: 'Add photos',
                    onPressed: () => _addPhotosTo(album.toAlbumItem()),
                  )
                : null;
            // An album plays as a slideshow from its bar (#4179), or on a
            // phone from the second row's tools; a selection plays from the
            // selection bar.
            final canSlideshow = album != null && photos.isNotEmpty;
            final slideshow = canSlideshow && !phone
                ? QuarkBarIconButton(
                    key: const ValueKey('photos_slideshow'),
                    icon: QuarkIcons.play_arrow,
                    tooltip: 'Slideshow',
                    onPressed: _playSlideshow,
                  )
                : null;
            final sort = PhotoSortButton(
              sortField: c.sortField,
              sortOrder: c.sortOrder,
              onChanged: c.setSort,
            );
            // A phone's bar holds two: Search and Select. Upload is the
            // + button and Sort joins the second row (#4150), with an album's
            // Select beside it.
            final actions = phone
                ? [search, ?selectOrAdd]
                : [
                    if (!secondRow) ...[upload, search],
                    ?slideshow,
                    ?albumSelect,
                    ?selectOrAdd,
                    sort,
                  ];
            return QuarkPageScaffold(
              title: 'Photos',
              icon: QuarkIcons.photo_library,
              actions: actions,
              onRefresh: manualRefresh,
              isRefreshing: isRefreshing,
              // The same selection bar Files and the trash swap in (#2311).
              // The library carries a second row with Duplicates in it, by
              // name (#2576); duplicates are found on the Quark, which Demo
              // mode never asks (#1666).
              appBar: c.selectionMode
                  ? FileSelectionBar(
                      selectedCount: selectedIds.length,
                      totalCount: photos.length,
                      onSelectAll: c.selectAll,
                      onDeselectAll: c.deselectAll,
                      onCancel: c.exitSelectionMode,
                      showDelete: false,
                      title: c.addingToAlbum == null
                          ? null
                          : 'Adding to ${c.addingToAlbum!.name}',
                      actions: [
                        if (c.addingToAlbum != null)
                          QuarkBarChip(
                            key: const ValueKey('photos_selection_done'),
                            icon: QuarkIcons.check,
                            label: 'Done (${selectedIds.length})',
                            keepLabel: true,
                            onPressed: selectedIds.isNotEmpty
                                ? () => _addSelectedTo(c.addingToAlbum!)
                                : null,
                          ),
                      ],
                    )
                  : secondRow
                  ? QuarkAppBar(
                      label: 'Photos',
                      icon: QuarkIcons.photo_library,
                      actions: actions,
                      onRefresh: manualRefresh,
                      isRefreshing: isRefreshing,
                      bottom: PhotosBarBottom(
                        title: album?.name ?? 'Library',
                        pinnedActions: phone
                            ? [sort, ?albumSelect]
                            : [upload, search],
                        onUploadToDevice: phone && c.canChooseUploadDevice
                            ? _uploadToDevice
                            : null,
                        onDuplicates: _demo
                            ? null
                            : () => context.go(AppRoutes.photoDuplicates),
                        onExport: _demo ? null : _exportPhotos,
                        onSlideshow: phone && canSlideshow
                            ? _playSlideshow
                            : null,
                        onPickLibrary: compact ? _openLibraryPicker : null,
                        onGridSize: compact ? _openGridSize : null,
                      ),
                    )
                  : null,
              drawer: const AppDrawer(activeSection: QuarkDrawerSection.photos),
              // A phone uploads from the same corner button as Files'
              // Create, into the album showing when there is one (#4150).
              floatingActionButton: phone && !c.selectionMode
                  ? QuarkCreateFab(
                      key: const ValueKey('photos_upload_fab'),
                      tooltip: 'Upload',
                      visible: _fabVisible,
                      onPressed: _uploadPhotos,
                    )
                  : null,
              // Every action a single photo has, on the whole selection
              // (#4154). Demo mode's samples only favorite; the rest would
              // ask a Quark.
              bottomBar: c.selectionMode && c.addingToAlbum == null
                  ? PhotoSelectionBar(
                      selectedCount: selectedIds.length,
                      onAddToAlbum: _pickAlbumForSelection,
                      allFavorites: c.selectionAllFavorites,
                      onFavorite: showingFavorites ? null : _favoriteSelection,
                      onDownload: _demo ? null : _downloadSelection,
                      // The share sheet takes one path.
                      onShare: _demo || selectedIds.length != 1
                          ? null
                          : _shareSelection,
                      onCopy: _demo ? null : _copySelection,
                      onSlideshow: _playSlideshow,
                      onRemoveFromAlbum: showingFavorites
                          ? () => _favoriteSelection(favorite: false)
                          : album != null && !album.isSystemAlbum
                          ? _removeSelectionFromAlbum
                          : null,
                      removeFromAlbumLabel: showingFavorites
                          ? 'Remove from favorites'
                          : 'Remove from album',
                      onDelete: _demo ? null : _deleteSelection,
                      quarkOnlyDisabledReason: c.selectionHasDevicePhoto
                          ? Errors.selectionHasPhonePhotos
                          : null,
                    )
                  : null,
              body: Column(
                children: [
                  if (_searchOpen)
                    PhotosSearchBar(
                      onChanged: c.setSearchQuery,
                      onClose: _toggleSearch,
                    ),
                  Expanded(
                    child: UploadDropZone(
                      enabled: !c.isUploading,
                      onDrop: _uploadDroppedFiles,
                      child: RefreshIndicator(
                        onRefresh: manualRefresh,
                        child: QuarkSplitView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          // A phone gets the library from the bar's
                          // picker chip, so the grid is the first thing
                          // under the bar there (#4149).
                          isSidebarOpen: false,
                          sidebarWidth: _libraryPane.width,
                          isSidebarCollapsed: _libraryPane.isCollapsed,
                          onSidebarWidthChanged: _libraryPane.setWidth,
                          onSidebarCollapsedChanged: _libraryPane.setCollapsed,
                          sidebar: PhotoLibraryNav(
                            controller: c,
                            onShowAlbum: _showAlbum,
                            onCreateAlbum: _createAlbum,
                            onAlbumMenu: _showAlbumActions,
                            sizeControl: PhotoColumnsSlider(
                              columns: c.columns,
                              minColumns: columnBounds.min,
                              maxColumns: columnBounds.max,
                              onColumnsChanged: c.setColumns,
                            ),
                          ),
                          slivers: [
                            SubAlbumStrip(
                              albums: c.subAlbums,
                              onSelected: (item) => _showAlbum(item.id),
                            ),
                            PhotoGrid(
                              photos: photos,
                              sections: c.photoSections,
                              crossAxisCount: PhotoGridConfig.columnsFor(
                                contentWidth,
                                c.columns,
                              ),
                              // The album being added to's own photos
                              // show checked, and cannot be picked
                              // (#3361).
                              selectedIds: {
                                ...selectedIds,
                                ...c.albumMemberIds,
                              },
                              selectionMode: c.selectionMode,
                              isLoading:
                                  isInitialLoad ||
                                  c.albumLoading ||
                                  c.isSearching,
                              // Unreachable has its own view in the empty state.
                              error: searchError != null
                                  ? Errors.message(
                                      searchError,
                                      'search your photos',
                                    )
                                  : albumError == null || c.quarkUnreachable
                                  ? null
                                  : Errors.message(
                                      albumError,
                                      'load the album',
                                    ),
                              hasMore: c.hasMore,
                              isLoadingMore: c.isLoadingMore,
                              emptyState: c.searchQuery.isNotEmpty
                                  ? EmptyStateWidget(
                                      icon: QuarkIcons.search,
                                      headline:
                                          'No photos match "${c.searchQuery}"',
                                      subtext: 'Search looks at file names.',
                                    )
                                  : PhotosEmptyState(
                                      unreachable: c.quarkUnreachable,
                                      showingFavorites: showingFavorites,
                                      albumName: album?.name,
                                      hostAddress: c.activeHost,
                                      onRetry: manualRefresh,
                                      onManageHosts: () => context.go(
                                        AppRoutes.settingsTab(
                                          SettingsTab.general,
                                        ),
                                      ),
                                      onUploadPhotos: c.isUploading
                                          ? null
                                          : _uploadPhotos,
                                      // Same action as the app bar's Add Photos, and
                                      // absent for the same albums (#992).
                                      onAddPhotosToAlbum:
                                          album != null && !album.isSystemAlbum
                                          ? () => _addPhotosTo(
                                              album.toAlbumItem(),
                                            )
                                          : null,
                                    ),
                              thumbnailBuilder: (context, photo) =>
                                  PhotoThumbnail(
                                    url: c.thumbnailUrl(photo.id),
                                    asset: c.assetFor(photo.id),
                                    path: c.thumbnailSource(photo.id)?.path,
                                    serial: c.thumbnailSource(photo.id)?.serial,
                                  ),
                              onTap: (i) => _onPhotoTap(photos, i),
                              // In an album the menu takes the long press; in
                              // the library it stays selection (#2276).
                              onLongPress: (i) =>
                                  c.selectFromLongPress(photos[i].id),
                              // Many photos in one gesture (#4171): the
                              // grid reports it, the controller picks.
                              onRangeSelect: (i) =>
                                  c.selectRangeTo(photos[i].id),
                              onDragSelectStart: c.beginDragSelection,
                              onDragSelectUpdate: (indices) =>
                                  c.updateDragSelection([
                                    for (final i in indices) photos[i].id,
                                  ]),
                              onDragSelectEnd: c.endDragSelection,
                              longPressOpensMenu:
                                  album != null && !c.selectionMode,
                              onMenu: _demo
                                  ? null
                                  : album == null
                                  ? (i, position) => _showLibraryPhotoActions(
                                      photos[i],
                                      position,
                                    )
                                  : (i, position) => _showAlbumItemActions(
                                      album,
                                      photos[i].id,
                                      position,
                                    ),
                              onDoubleTap: (i) => _toggleFavorite(photos[i].id),
                            ),
                          ],
                        ),
                      ),
                    ),
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

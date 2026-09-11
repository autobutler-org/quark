import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark/controllers/photo_bytes_cache.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/pages/album_page.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/favorites_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/image_viewer_config.dart';
import 'package:quark/widgets/image_viewer/current_photo.dart';
import 'package:quark/widgets/image_viewer/desktop_body.dart';
import 'package:quark/widgets/image_viewer/image_viewer_app_bar.dart';
import 'package:quark/widgets/image_viewer/mobile_body.dart';
import 'package:quark/widgets/image_viewer/photo_area.dart';
import 'package:quark/widgets/image_viewer/shortcut_row.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:quark/widgets/photos/album_picker_sheet.dart';
import 'package:quark/utils/quark_widget_items.dart';

const _kSidebarOpenKey = 'photo_viewer_sidebar_open';

// How long the page settles when the keyboard or a chevron turns it.
const _kPageAnimDuration = Duration(milliseconds: 250);

/// A full-screen photo viewer with metadata sidebar (desktop) / bottom drawer
/// (mobile), action toolbar, and keyboard shortcuts.
///
/// Required: [name]. Pass [bytes] when they are already in hand; leave them
/// null with a [relPath] and the viewer opens at once and downloads the photo
/// itself, so the user is not left staring at the page they came from (#1564).
///
/// Optional Quark-device extras (enable metadata, download, delete, album actions):
///   [relPath], [serial].
///
/// Optional context: [sourceAlbum] — when set, the more menu shows
/// "Remove from [Album]" instead of "Add to Album."
///
/// Navigation: pass [initialIndex], [imageCount], [onLoadImage].
/// Keyboard: ← → navigate, Escape closes, i toggles sidebar, f toggles
/// favorite, r rotates 90° CW.
class ImageViewerPage extends StatefulWidget {
  final Uint8List? bytes;
  final String name;
  final int initialIndex;
  final int imageCount;

  /// Returns (bytes, name, relPath, serial). relPath and serial may be null
  /// for local-device assets that have no Quark path.
  final Future<(Uint8List?, String, String?, String?)> Function(int index)?
  onLoadImage;

  /// Warms whatever cache backs [onLoadImage] for [index], in the background.
  ///
  /// Separate from [onLoadImage] because a prefetch must stay invisible: it
  /// may not show the user anything, and it may not react to a failure the way
  /// a navigation does (a 404 on a photo the user never asked for is not a
  /// reason to refetch the grid behind them).
  final Future<void> Function(int index)? onPrefetchImage;

  final Future<int> Function()? getImageCount;

  /// Relative path on the Quark device (enables metadata & server actions).
  final String? relPath;

  /// Device serial (paired with [relPath]).
  final String? serial;

  /// Album the user navigated from — makes the more menu show
  /// "Remove from [Album]" instead of "Add to Album."
  final PhotoAlbum? sourceAlbum;

  const ImageViewerPage({
    super.key,
    this.bytes,
    required this.name,
    this.initialIndex = 0,
    this.imageCount = 1,
    this.onLoadImage,
    this.onPrefetchImage,
    this.getImageCount,
    this.relPath,
    this.serial,
    this.sourceAlbum,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage>
    with SingleTickerProviderStateMixin {
  // Navigation state
  late int _currentIndex;
  // Null until the viewer's own download of [ImageViewerPage.relPath] lands.
  Uint8List? _currentBytes;
  String? _loadError;
  late String _currentName;
  late String? _currentRelPath;
  late String? _currentSerial;
  bool _loading = false;
  late int _liveImageCount;

  // The photo most recently asked for. A download whose target no longer
  // matches this has been superseded by a later swipe and drops its result.
  late int _targetIndex;

  // UI state
  bool _sidebarOpen = true;
  bool _isFavorite = false;
  int _rotationQuarters = 0; // 0/1/2/3 × 90°

  // Set to true whenever the photo list in the caller may need a refresh
  // (photo deleted, or album membership changed). Returned via pop().
  bool _listChanged = false;
  late AnimationController _rotationAnim;
  late Animation<double> _rotationValue;

  // Metadata
  PhotoMetadata? _metadata;
  bool _metadataLoading = false;

  // Live Photo playback
  VideoPlayerController? _liveVideoController;
  bool _liveVideoPlaying = false;
  bool _liveVideoReady = false;

  SharedPreferences? _prefs;
  final _focusNode = FocusNode();

  // Zoom/pan state of the photo. Swipe-to-navigate only applies while the
  // photo sits at 1x; once zoomed, a horizontal drag pans the photo, and the
  // downscaled decode stops being enough so the full-resolution one is worth
  // paying for.
  final _zoomController = TransformationController();
  bool _zoomedIn = false;
  late PageController _pageController;

  // DraggableScrollableSheet controller for mobile drawer
  final _drawerController = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _targetIndex = widget.initialIndex;
    _currentBytes = widget.bytes;
    _currentName = widget.name;
    _currentRelPath = widget.relPath;
    _currentSerial = widget.serial;
    _liveImageCount = widget.imageCount;
    _pageController = PageController(initialPage: widget.initialIndex);
    _zoomController.addListener(_onZoomChanged);

    _rotationAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _rotationValue = Tween<double>(begin: 0, end: 0).animate(_rotationAnim);

    _initPrefs();
    _prefetchNeighbors();
    if (_currentBytes == null) _loadOwnBytes();
  }

  /// Downloads the photo for a viewer opened without its bytes. A failure
  /// stays on screen in place of the photo — there is no other photo to fall
  /// back to.
  Future<void> _loadOwnBytes() async {
    Uint8List? bytes;
    Object? error;
    try {
      bytes = await FilesService.downloadFileBytes(
        _currentRelPath ?? '',
        serial: _currentSerial,
      );
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() {
      _currentBytes = bytes;
      if (bytes == null) _loadError = Errors.message(error, 'load the photo');
    });
  }

  @override
  void dispose() {
    _liveVideoController?.dispose();
    _rotationAnim.dispose();
    _focusNode.dispose();
    _drawerController.dispose();
    _zoomController.removeListener(_onZoomChanged);
    _zoomController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _prefs = prefs;
    final sidebarOpen = prefs.getBool(_kSidebarOpenKey) ?? true;

    // Rotation and favorite state come from the server metadata response for
    // Quark photos; leave them at defaults here and let
    // _loadMetadataForCurrent apply the server values.
    setState(() => _sidebarOpen = sidebarOpen);
    _loadMetadata();
  }

  // Rotation is always server-backed. Only Quark photos (with a relPath)
  // support rotation — local device assets have no server path to key on.
  bool get _isQuarkPhoto =>
      _currentRelPath != null && _currentRelPath!.isNotEmpty;

  // --- Navigation ---

  // Measured from the newest requested photo so the chevrons stay live, and
  // keep stepping, while a download is still in flight.
  bool get _hasPrev => _targetIndex > 0;
  bool get _hasNext => _targetIndex < _liveImageCount - 1;

  // A PageView carries the swipe so the photo tracks the finger and settles
  // with an animation (#1707). The keyboard and the chevrons drive the same
  // controller so every route to the next photo animates the same way.
  //
  // The step counts from the newest requested photo rather than the one on
  // screen, so a second press while the first is still downloading moves on
  // instead of asking for the same photo twice (#1710).
  void _goToPage(int delta) {
    final target = _targetIndex + delta;
    if (target < 0 || target >= _liveImageCount) return;
    if (!_pageController.hasClients) {
      _navigate(target);
      return;
    }
    _pageController.animateToPage(
      target,
      duration: _kPageAnimDuration,
      curve: Curves.easeOut,
    );
  }

  Future<void> _onPageChanged(int index) async {
    if (index == _currentIndex) return;
    await _navigate(index);
    // The load failed, so there are no bytes for the page the finger settled
    // on. Put the view back on the photo we still have — but only once nothing
    // is in flight, because a target that no longer matches what is on screen
    // means the user has swiped on again and this recovery would drag them
    // back off the photo they asked for (#1710).
    if (!mounted || !_pageController.hasClients) return;
    if (_targetIndex != _currentIndex || index == _currentIndex) return;
    _pageController.jumpToPage(_currentIndex);
  }

  // A zoomed photo pans inside the InteractiveViewer, so the PageView has to
  // stop scrolling until it is back at 1x, and the photo has to be decoded
  // again at full resolution. Both start the moment the user pinches, so one flag
  // and one threshold cover them (#1707, #1710).
  void _onZoomChanged() {
    final zoomed =
        _zoomController.value.getMaxScaleOnAxis() >
        ImageViewerConfig.zoomedInScale;
    if (zoomed != _zoomedIn) setState(() => _zoomedIn = zoomed);
  }

  /// Downloads the photos either side of this one into the loader's cache.
  ///
  /// The next thing the user does is nearly always "next photo" or "previous
  /// photo", so paying for those while they look at this one is what makes the
  /// step feel instant. Nothing here is awaited, nothing here touches state,
  /// and a failure is swallowed: a photo the user never asked for must not
  /// produce a snackbar, and the widget may well be gone before the download
  /// lands (#1710).
  void _prefetchNeighbors() {
    final prefetch = widget.onPrefetchImage;
    if (prefetch == null) return;
    for (var delta = 1; delta <= ImageViewerConfig.prefetchWindow; delta++) {
      for (final index in [_currentIndex - delta, _currentIndex + delta]) {
        if (index < 0 || index >= _liveImageCount) continue;
        unawaited(prefetch(index).catchError((Object _) {}));
      }
    }
  }

  /// Shows the photo at [newIndex], downloading it first.
  ///
  /// Navigations coalesce: the newest one wins. A request that arrives while
  /// an earlier download is still in flight used to be dropped on the floor,
  /// which meant swiping faster than the network could answer threw away every
  /// swipe but the first — and left [_onPageChanged] snapping the view back to
  /// the photo it already had. Now every request runs, and each one checks
  /// after every await whether the user has since asked for somewhere else; if
  /// they have, it discards its result rather than yanking them back to a
  /// photo they have already passed. The bytes it downloaded still land in
  /// [PhotoBytesCache], so a superseded load is not wasted (#1710).
  Future<void> _navigate(int newIndex) async {
    if (!mounted) return;
    if (newIndex < 0 || newIndex >= _liveImageCount) return;
    if (widget.onLoadImage == null) return;

    _targetIndex = newIndex;
    setState(() => _loading = true);
    try {
      final (bytes, name, relPath, serial) = await widget.onLoadImage!(
        newIndex,
      );
      if (!mounted || _targetIndex != newIndex) return;
      if (bytes == null) {
        _targetIndex = _currentIndex;
        setState(() => _loading = false);
        _showLoadFailure(null, newIndex);
        return;
      }
      int updatedCount = _liveImageCount;
      if (widget.getImageCount != null) {
        updatedCount = await widget.getImageCount!();
      }
      if (!mounted || _targetIndex != newIndex) return;

      _disposeLiveVideo();
      _zoomController.value = Matrix4.identity();
      // Reset rotation and favorite to defaults; _loadMetadataForCurrent
      // will apply server-persisted values once metadata arrives.
      setState(() {
        _currentIndex = newIndex;
        _currentBytes = bytes;
        _currentName = name;
        _currentRelPath = relPath;
        _currentSerial = serial;
        _liveImageCount = updatedCount;
        _loading = false;
        _metadata = null;
        _isFavorite = false;
        _rotationQuarters = 0;
        _rotationValue = Tween<double>(begin: 0, end: 0).animate(_rotationAnim);
      });
      _loadMetadataForCurrent();
      _prefetchNeighbors();
    } catch (e) {
      debugPrint('ImageViewerPage: failed to load image $newIndex: $e');
      if (!mounted || _targetIndex != newIndex) return;
      _targetIndex = _currentIndex;
      setState(() => _loading = false);
      _showLoadFailure(e, newIndex);
    }
  }

  /// Tells the user a photo wouldn't load, and offers another go at it.
  ///
  /// A 404 is the one answer that means the photo really is gone, so it gets
  /// the "no longer there" copy and no retry. Everything else — a dropped
  /// request, a busy Quark, a list that moved underneath us — is worth trying
  /// again, so the snackbar carries a Retry rather than stranding the viewer
  /// on the photo it was already showing (#1708).
  void _showLoadFailure(Object? error, int newIndex) {
    final gone = error is ApiException && error.statusCode == 404;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Errors.message(error, 'load the photo')),
        action: gone
            ? null
            : SnackBarAction(
                label: 'Retry',
                onPressed: () => _navigate(newIndex),
              ),
      ),
    );
  }

  // --- Metadata ---

  Future<void> _loadMetadata() => _loadMetadataForCurrent();

  Future<void> _loadMetadataForCurrent() async {
    final relPath = _currentRelPath;
    if (relPath == null || relPath.isEmpty) return;
    setState(() => _metadataLoading = true);
    try {
      final meta = await FilesService.getPhotoMetadata(
        relPath,
        serial: _currentSerial,
      );
      if (!mounted) return;
      // Apply server-persisted rotation and favorite state for this photo.
      final quarters = meta.rotationQuarters.clamp(0, 3);
      setState(() {
        _metadata = meta;
        _metadataLoading = false;
        _isFavorite = meta.isFavorite;
        _rotationQuarters = quarters;
        _rotationValue = Tween<double>(
          begin: quarters * math.pi / 2,
          end: quarters * math.pi / 2,
        ).animate(_rotationAnim);
      });
      if (meta.isLivePhoto) _prepareLiveVideo();
    } catch (_) {
      if (mounted) setState(() => _metadataLoading = false);
    }
  }

  // --- Live Photo ---

  void _prepareLiveVideo() {
    _disposeLiveVideo();
    final videoPath = _metadata?.livePhotoVideoPath;
    if (videoPath == null) return;

    final url = FilesService.constructMediaUrl(
      videoPath,
      serial: _currentSerial,
    );
    final controller = VideoPlayerController.networkUrl(url);
    _liveVideoController = controller;
    controller.setLooping(true);
    controller
        .initialize()
        .then((_) {
          if (!mounted || _liveVideoController != controller) return;
          setState(() => _liveVideoReady = true);
        })
        .catchError((_) {});
  }

  void _disposeLiveVideo() {
    _liveVideoController?.dispose();
    _liveVideoController = null;
    _liveVideoReady = false;
    _liveVideoPlaying = false;
  }

  void _startLivePlayback() {
    if (!_liveVideoReady || _liveVideoController == null) return;
    _liveVideoController!.seekTo(Duration.zero);
    _liveVideoController!.play();
    setState(() => _liveVideoPlaying = true);
  }

  void _stopLivePlayback() {
    _liveVideoController?.pause();
    if (mounted) setState(() => _liveVideoPlaying = false);
  }

  // --- Actions ---

  void _toggleSidebar() {
    setState(() => _sidebarOpen = !_sidebarOpen);
    _prefs?.setBool(_kSidebarOpenKey, _sidebarOpen);
  }

  Future<void> _toggleFavorite() async {
    if (!_isQuarkPhoto) return;
    final relPath = _currentRelPath!;
    final serial = _currentSerial;

    // Optimistic update.
    setState(() => _isFavorite = !_isFavorite);

    try {
      final nowFav = await FavoritesService.toggle(
        relPath: relPath,
        serial: serial?.isNotEmpty == true ? serial : null,
      );
      if (!mounted) return;
      // Reconcile with server truth in case of any race, and flag the list
      // as changed so the caller refreshes (e.g. removes from Favorites tab).
      setState(() => _isFavorite = nowFav);
      _listChanged = true;
    } catch (e) {
      if (!mounted) return;
      // Roll back and surface the error.
      setState(() => _isFavorite = !_isFavorite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'update the favorite'))),
      );
    }
  }

  Future<void> _rotate() async {
    if (!_isQuarkPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rotation is only supported for Quark photos'),
        ),
      );
      return;
    }

    final oldQuarters = _rotationQuarters;
    final oldAngle = oldQuarters * math.pi / 2;
    final newQuarters = (oldQuarters + 1) % 4;
    final newAngle =
        newQuarters * math.pi / 2 +
        (newQuarters == 0 ? math.pi * 2 : 0); // always animate forward

    // Optimistically apply the rotation in the UI.
    setState(() => _rotationQuarters = newQuarters);
    _rotationValue = Tween<double>(
      begin: oldAngle,
      end: newAngle,
    ).animate(CurvedAnimation(parent: _rotationAnim, curve: Curves.easeOut));
    _rotationAnim.forward(from: 0);

    try {
      await FilesService.rotatePhoto(
        _currentRelPath!,
        serial: _currentSerial,
        rotationQuarters: newQuarters,
      );
      // Evict the old decoded image from Flutter's Dart-level image cache so
      // the next Image.network load actually hits the network rather than
      // being served from memory. Combined with Cache-Control: no-cache on
      // the server, the revalidation request picks up the new ETag
      // (rotation-aware) and gets the updated thumbnail bytes.
      final thumbUrl = FilesService.constructThumbnailUrl(
        _currentRelPath!,
        serial: _currentSerial,
      ).toString();
      await NetworkImage(thumbUrl).evict();
      // Same reason, for the full-resolution bytes: the cache is keyed by path
      // and serial, neither of which a rotation changes (#1710).
      PhotoBytesCache.instance.evict(
        PhotoBytesCache.key(_currentRelPath!, _currentSerial),
      );
      _listChanged = true;
    } catch (e) {
      // Roll back the visual rotation and inform the user.
      if (!mounted) return;
      setState(() {
        _rotationQuarters = oldQuarters;
        _rotationValue = Tween<double>(begin: newAngle, end: oldAngle).animate(
          CurvedAnimation(parent: _rotationAnim, curve: Curves.easeOut),
        );
      });
      _rotationAnim.forward(from: 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'rotate the photo'))),
      );
    }
  }

  Future<void> _download() async {
    final relPath = _currentRelPath;
    if (relPath == null) return;
    try {
      await FilesService.saveFile(
        relPath,
        serial: _currentSerial,
        fileName: _currentName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'download the photo'))),
        );
      }
    }
  }

  Future<void> _addToAlbum() async {
    final relPath = _currentRelPath;
    if (relPath == null) return;
    final album = await AlbumPickerSheetHost.show(
      context,
      selectedCount: 1,
      loadAlbums: () async => [
        for (final album in await AlbumService.listAlbums(tree: true))
          album.toAlbumItem(),
      ],
    );
    if (album == null || !mounted) return;
    try {
      await AlbumService.addPhotoToAlbum(
        album.id,
        deviceSerial: _currentSerial ?? '',
        relPath: relPath,
      );
      if (!mounted) return;
      _listChanged = true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added to ${album.name}')));
      _loadMetadata(); // refresh album list in sidebar
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'add it to the album'))),
        );
      }
    }
  }

  Future<void> _removeFromAlbum(PhotoAlbum album) async {
    final relPath = _currentRelPath;
    if (relPath == null) return;
    try {
      await AlbumService.removePhotoFromAlbum(
        album.id,
        deviceSerial: _currentSerial ?? '',
        relPath: relPath,
      );
      if (!mounted) return;
      _listChanged = true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Removed from ${album.name}')));
      _loadMetadata();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Errors.message(e, 'remove it from the album')),
          ),
        );
      }
    }
  }

  Future<void> _navigateToAlbum(AlbumRef ref) async {
    // Construct a minimal PhotoAlbum from the AlbumRef already in hand —
    // no extra fetch needed since AlbumPage only needs id + name.
    final album = PhotoAlbum(
      id: ref.id,
      name: ref.name,
      parentId: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      itemCount: 0,
    );
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AlbumPage(album: album)));
  }

  Future<void> _makeACopy() async {
    final relPath = _currentRelPath;
    if (relPath == null) return;
    try {
      final newRelPath = await FilesService.copyPhoto(
        relPath,
        serial: _currentSerial,
      );
      if (!mounted) return;
      final newName = newRelPath.contains('/')
          ? newRelPath.substring(newRelPath.lastIndexOf('/') + 1)
          : newRelPath;
      _listChanged = true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Copy saved as $newName')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'copy the photo'))),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final relPath = _currentRelPath;
    if (relPath == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete photo?'),
        content: Text(
          'This permanently deletes "$_currentName" from the server. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final dir = relPath.contains('/')
          ? relPath.substring(0, relPath.lastIndexOf('/'))
          : '';
      await FilesService.deleteFile(
        dir,
        _currentName,
        deviceSerial: _currentSerial,
      );
      if (!mounted) return;
      _listChanged = true;
      Navigator.of(context).pop(_listChanged);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'delete the photo'))),
        );
      }
    }
  }

  // --- Keyboard ---

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _goToPage(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _goToPage(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop(_listChanged);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyI:
        _toggleSidebar();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        _toggleFavorite();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyR:
        _rotate();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.question:
        _showShortcutsDialog(context);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;
    final isLive = _metadata?.isLivePhoto ?? false;
    final bytes = _currentBytes;
    final loadError = _loadError;
    final photoArea = PhotoArea(
      currentPhoto: bytes != null
          ? CurrentPhoto(
              bytes: bytes,
              rotation: _rotationValue,
              zoomController: _zoomController,
              zoomedIn: _zoomedIn,
              liveVideoPlaying: _liveVideoPlaying,
              liveVideoController: _liveVideoController,
            )
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loadError == null)
                    const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    loadError ?? _currentName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
      pageController: _pageController,
      currentIndex: _currentIndex,
      imageCount: _liveImageCount,
      onPageChanged: _onPageChanged,
      zoomedIn: _zoomedIn,
      loading: _loading,
      isLive: isLive,
      liveVideoReady: _liveVideoReady,
      liveVideoPlaying: _liveVideoPlaying,
      onStartLivePlayback: _startLivePlayback,
      onStopLivePlayback: _stopLivePlayback,
      onTapDismissSidebar: !isDesktop && _sidebarOpen
          ? () => setState(() => _sidebarOpen = false)
          : null,
    );
    // `canPop: false` reports `RoutePopDisposition.doNotPop`, which is what
    // turns off the iOS left-edge back-swipe on this route. Without it that
    // edge gesture beats the photo page view near the bezel and drops the
    // user out of the viewer mid-swipe (#1707). Every other exit still calls
    // `Navigator.pop` directly, which never consults this scope, so only a
    // system back arrives here and it is popped by hand.
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_listChanged);
      },
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (e) => _handleKey(_focusNode, e),
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: ImageViewerAppBar(
            isDesktop: isDesktop,
            currentIndex: _currentIndex,
            imageCount: _liveImageCount,
            hasPrev: _hasPrev,
            hasNext: _hasNext,
            onPrevious: () => _goToPage(-1),
            onNext: () => _goToPage(1),
            isFavorite: _isFavorite,
            sidebarOpen: _sidebarOpen,
            relPath: _currentRelPath,
            sourceAlbum: widget.sourceAlbum,
            onClose: () => Navigator.of(context).pop(_listChanged),
            onToggleFavorite: _toggleFavorite,
            onRotate: _rotate,
            onDownload: _download,
            onToggleSidebar: _toggleSidebar,
            onAddToAlbum: _addToAlbum,
            onRemoveFromAlbum: () => _removeFromAlbum(widget.sourceAlbum!),
            onMakeACopy: _makeACopy,
            onDelete: _confirmDelete,
            onShowShortcuts: () => _showShortcutsDialog(context),
          ),
          body: isDesktop
              ? DesktopBody(
                  photoArea: photoArea,
                  sidebarOpen: _sidebarOpen,
                  name: _currentName,
                  metadata: _metadata,
                  loading: _metadataLoading,
                  onAlbumTap: _navigateToAlbum,
                )
              : MobileBody(
                  photoArea: photoArea,
                  sidebarOpen: _sidebarOpen,
                  drawerController: _drawerController,
                  name: _currentName,
                  metadata: _metadata,
                  loading: _metadataLoading,
                  onAlbumTap: _navigateToAlbum,
                ),
        ),
      ),
    );
  }

  void _showShortcutsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Keyboard shortcuts',
          style: TextStyle(color: Colors.white),
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShortcutRow(
                shortcut: '← →',
                description: 'Previous / Next photo',
              ),
              ShortcutRow(shortcut: 'F', description: 'Toggle favorite'),
              ShortcutRow(shortcut: 'R', description: 'Rotate 90° clockwise'),
              ShortcutRow(shortcut: 'I', description: 'Toggle info panel'),
              ShortcutRow(shortcut: 'Esc', description: 'Close viewer'),
              ShortcutRow(shortcut: '?', description: 'Show this help'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/photos/add_to_album_sheet.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark/services/app_settings.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({required this.album, super.key});

  final PhotoAlbum album;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  List<PhotoAlbumItem> _items = [];
  bool _loading = true;
  bool _isOpeningPhoto = false;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  Object? _error;
  int _crossAxisCount = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AlbumService.listAlbumItems(widget.album.id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _openAddPhotosMode() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotosPage(addingToAlbum: widget.album),
      ),
    );
    // Reload after returning in case photos were added
    await _load();
  }

  Future<void> _removeItem(PhotoAlbumItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from album?'),
        content: const Text(
          'This removes the photo from this album. The file on disk is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AlbumService.removePhotoFromAlbum(
        widget.album.id,
        deviceSerial: item.deviceSerial,
        relPath: item.relPath,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Errors.message(e, 'remove the photo from the album')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.name),
        actions: [
          TextButton.icon(
            onPressed: _openAddPhotosMode,
            icon: const Icon(QuarkIcons.add_rounded, size: 18),
            label: const Text('Add Photos'),
          ),
          IconButton(
            icon: const Icon(QuarkIcons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'grid-up') {
                setState(
                  () => _crossAxisCount = (_crossAxisCount - 1).clamp(1, 6),
                );
              } else if (value == 'grid-down') {
                setState(
                  () => _crossAxisCount = (_crossAxisCount + 1).clamp(1, 6),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'grid-up',
                child: ListTile(
                  leading: Icon(QuarkIcons.crop_square_outlined),
                  title: Text('Larger photos'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'grid-down',
                child: ListTile(
                  leading: Icon(QuarkIcons.grid_view_outlined),
                  title: Text('Smaller photos'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const AppThemeToggle(),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? (isQuarkUnreachableError(_error!)
                ? QuarkDisconnectedView(
                    hostAddress: AppSettings.instance.activeHost,
                    onRetry: _load,
                  )
                : Center(
                    child: Text(Errors.message(_error!, 'load the album')),
                  ))
          : _items.isEmpty
          ? EmptyStateWidget(
              icon: QuarkIcons.photo_album_outlined,
              headline: 'No photos yet',
              subtext:
                  'Add photos to "${widget.album.name}" from the Photos view.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: GridView.builder(
                padding: const EdgeInsets.all(2),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _crossAxisCount,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: _items.length,
                itemBuilder: (context, idx) {
                  final item = _items[idx];
                  final url = FilesService.constructThumbnailUrl(
                    item.relPath,
                    serial: item.deviceSerial,
                  );
                  return GestureDetector(
                    onTap: () async {
                      if (_isOpeningPhoto) return;
                      _isOpeningPhoto = true;
                      try {
                        final navigator = Navigator.of(context);
                        final bytes = await FilesService.downloadFileBytes(
                          item.relPath,
                          serial: item.deviceSerial,
                        );
                        if (bytes == null || !mounted) return;
                        final changed = await navigator.push<bool>(
                          MaterialPageRoute(
                            builder: (_) => ImageViewerPage(
                              bytes: bytes,
                              name: item.relPath.split('/').last,
                              initialIndex: idx,
                              imageCount: _items.length,
                              relPath: item.relPath,
                              serial: item.deviceSerial,
                              sourceAlbum: widget.album,
                              getImageCount: () async => _items.length,
                              onLoadImage: (newIdx) async {
                                if (newIdx >= _items.length) {
                                  return (null, '', null, null);
                                }
                                final ni = _items[newIdx];
                                final b = await FilesService.downloadFileBytes(
                                  ni.relPath,
                                  serial: ni.deviceSerial,
                                );
                                return (
                                  b,
                                  ni.relPath.split('/').last,
                                  ni.relPath,
                                  ni.deviceSerial,
                                );
                              },
                            ),
                          ),
                        );
                        if (changed == true) await _load();
                      } finally {
                        if (mounted) setState(() => _isOpeningPhoto = false);
                      }
                    },
                    onLongPress: () => _showItemMenu(context, item),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          url.toString(),
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: colorScheme.surfaceContainerHighest,
                            );
                          },
                          errorBuilder: (context, error, stack) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(
                              QuarkIcons.broken_image_outlined,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.3,
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

  void _showItemMenu(BuildContext context, PhotoAlbumItem item) {
    showModalBottomSheet<void>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuarkColors.radiusLg),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(QuarkIcons.photo_album_outlined),
              title: const Text('Add to another album'),
              onTap: () {
                Navigator.of(ctx).pop();
                AddToAlbumSheetHost.show(
                  context,
                  deviceSerial: item.deviceSerial,
                  relPath: item.relPath,
                );
              },
            ),
            ListTile(
              leading: Icon(
                QuarkIcons.remove_circle_outline,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                'Remove from album',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _removeItem(item);
              },
            ),
          ],
        ),
      ),
    );
  }
}

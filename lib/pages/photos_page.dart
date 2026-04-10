import 'package:autobutler/models/cirrus_file_node.dart';
import 'package:autobutler/utils/auto_refresh_mixin.dart';
import 'package:autobutler/widgets/core/empty_state_widget.dart';
import 'package:autobutler/widgets/refresh_icon_button.dart';
import 'package:autobutler/pages/image_viewer_page.dart';
import 'package:autobutler/services/app_settings.dart';
import 'package:autobutler/services/cirrus_service.dart';
import 'package:autobutler/widgets/autobutler_drawer.dart';
import 'package:autobutler/widgets/layout/autobutler_app_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:autobutler/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key});

  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

enum PhotoCategory { cirrus, mobile, all }

class PhotoItem {
  final CirrusFileNode? cirrus;
  final AssetEntity? asset;
  final bool isCirrus;

  PhotoItem._({this.cirrus, this.asset}) : isCirrus = cirrus != null;

  factory PhotoItem.fromCirrus(CirrusFileNode c) => PhotoItem._(cirrus: c);
  factory PhotoItem.fromAsset(AssetEntity a) => PhotoItem._(asset: a);
}

class _PhotosPageState extends State<PhotosPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  static const int _defaultCrossAxisCount = 4;
  static const int _minPreviewColumns = 1;
  static const int _maxPreviewColumns = 8;
  static const double _minTileWidth = 80;
  static const int _pageSize = 50;

  Future<List<PhotoItem>> _photosFuture = Future.value(const <PhotoItem>[]);

  // Cirrus pagination state
  List<PhotoItem> _cirrusPhotos = <PhotoItem>[];
  int _cirrusTotal = 0;
  int _cirrusOffset = 0;
  bool _isLoadingMoreCirrus = false;
  bool _cirrusInitialLoadDone = false;

  List<PhotoItem> _mobilePhotos = const <PhotoItem>[];

  bool _noHostSelected = false;
  bool _categoriesExpanded = false;
  int _previewColumns = _defaultCrossAxisCount;
  PhotoCategory _selectedCategory = PhotoCategory.cirrus;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    // Trigger fetch when scrolled past 80%
    if (currentScroll >= maxScroll * 0.8) {
      _loadMoreCirrusPhotos();
    }
  }

  /// Load the next page of cirrus photos via the paginated endpoint.
  Future<void> _loadMoreCirrusPhotos() async {
    if (_isLoadingMoreCirrus) return;
    if (_cirrusOffset >= _cirrusTotal && _cirrusInitialLoadDone) return;

    setState(() {
      _isLoadingMoreCirrus = true;
    });

    try {
      final response = await CirrusService.getPhotos(
        offset: _cirrusOffset,
        limit: _pageSize,
      );

      final newPhotos = response.photos
          .map(
            (p) => PhotoItem.fromCirrus(
              CirrusFileNode(
                name: p.fileName,
                size: p.size,
                isDir: false,
                deviceName: '',
                devicePath: '',
                deviceSerial: p.serial,
                dirPath: p.relPath,
              ),
            ),
          )
          .toList(growable: false);

      setState(() {
        _cirrusPhotos = [..._cirrusPhotos, ...newPhotos];
        _cirrusTotal = response.total;
        _cirrusOffset += newPhotos.length;
        _cirrusInitialLoadDone = true;
        _isLoadingMoreCirrus = false;
        // Rebuild the future so FutureBuilder picks up the new list
        _photosFuture = _photosForCategory(_selectedCategory);
      });
    } catch (_) {
      debugPrint('[photos_page.dart] Error loading more cirrus photos');
      setState(() {
        _isLoadingMoreCirrus = false;
        _cirrusInitialLoadDone = true;
      });
    }
  }

  /// Initial load of cirrus photos (first page).
  Future<List<PhotoItem>> _loadCirrusPhotos() async {
    if (_noHostSelected) return const <PhotoItem>[];

    _cirrusPhotos = <PhotoItem>[];
    _cirrusOffset = 0;
    _cirrusTotal = 0;
    _cirrusInitialLoadDone = false;

    try {
      final response = await CirrusService.getPhotos(
        offset: 0,
        limit: _pageSize,
      );

      final items = response.photos
          .map(
            (p) => PhotoItem.fromCirrus(
              CirrusFileNode(
                name: p.fileName,
                size: p.size,
                isDir: false,
                deviceName: '',
                devicePath: '',
                deviceSerial: p.serial,
                dirPath: p.relPath,
              ),
            ),
          )
          .toList(growable: false);

      _cirrusPhotos = items;
      _cirrusTotal = response.total;
      _cirrusOffset = items.length;
      _cirrusInitialLoadDone = true;
      return items;
    } catch (_) {
      debugPrint('[photos_page.dart] Error loading initial cirrus photos');
      _cirrusInitialLoadDone = true;
      return const <PhotoItem>[];
    }
  }

  Future<void> _primeSources() async {
    final cirrusFuture = _safeLoadPhotos(_loadCirrusPhotos);
    if (kIsWeb) {
      _cirrusPhotos = await cirrusFuture;
      _mobilePhotos = const <PhotoItem>[];
      return;
    }

    final mobileFuture = _safeLoadPhotos(_loadMobilePhotos);
    final lists = await Future.wait([cirrusFuture, mobileFuture]);
    _cirrusPhotos = lists[0];
    _mobilePhotos = lists[1];
  }

  Future<List<PhotoItem>> _safeLoadPhotos(
    Future<List<PhotoItem>> Function() loader,
  ) async {
    try {
      return await loader();
    } catch (_) {
      debugPrint('[photos_page.dart] Error in catch block');
      return const <PhotoItem>[];
    }
  }

  Future<List<PhotoItem>> _photosForCategory(PhotoCategory category) async {
    if (kIsWeb) {
      return _cirrusPhotos;
    }

    switch (category) {
      case PhotoCategory.cirrus:
        return _cirrusPhotos;
      case PhotoCategory.mobile:
        return _mobilePhotos;
      case PhotoCategory.all:
        return [..._cirrusPhotos, ..._mobilePhotos];
    }
  }

  Future<List<PhotoItem>> _loadMobilePhotos() async {
    // Only attempt mobile photo loading on Android or iOS devices.
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return [];
    }

    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) return [];

    // Load from the device 'All' album.
    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.image,
    );
    if (paths.isEmpty) return [];

    final AssetPathEntity all = paths.first;
    // Lazy: fetch an initial safe page size; UI can be extended to load more on scroll.
    final List<AssetEntity> assets = await all.getAssetListPaged(
      page: 0,
      size: 200,
    );
    return assets.map((a) => PhotoItem.fromAsset(a)).toList(growable: false);
  }

  Future<void> _selectCategory(PhotoCategory cat) async {
    setState(() {
      _selectedCategory = cat;
      _categoriesExpanded = false;
      _photosFuture = _photosForCategory(cat);
    });
  }

  @override
  Future<void> refresh() async {
    _noHostSelected = AppSettings.instance.activeHost == null;
    await _primeSources();
    setState(() {
      _photosFuture = _photosForCategory(_selectedCategory);
    });
    await _photosFuture;
  }

  bool get _hasMoreCirrus =>
      _cirrusInitialLoadDone && _cirrusOffset < _cirrusTotal;

  int _minColumnsByScale() {
    return _minPreviewColumns;
  }

  int _maxColumnsByScale() {
    return _maxPreviewColumns;
  }

  int _maxColumnsByWidth(double availableWidth) {
    return (availableWidth / _minTileWidth).floor().clamp(1, 100);
  }

  int _effectiveCrossAxisCount(double availableWidth) {
    final maxByWidth = _maxColumnsByWidth(availableWidth);
    var minColumns = _minColumnsByScale();
    var maxColumns = _maxColumnsByScale();

    if (minColumns > maxByWidth) {
      minColumns = maxByWidth;
    }
    if (maxColumns > maxByWidth) {
      maxColumns = maxByWidth;
    }
    if (minColumns > maxColumns) {
      minColumns = maxColumns;
    }

    return _previewColumns.clamp(minColumns, maxColumns);
  }

  Widget _buildSidebar(
    BuildContext context,
    double availableWidth,
    int cirrusCount,
    int mobileCount, {
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final maxByWidth = _maxColumnsByWidth(availableWidth);
    var minColumns = _minColumnsByScale();
    var maxColumns = _maxColumnsByScale();
    if (minColumns > maxByWidth) {
      minColumns = maxByWidth;
    }
    if (maxColumns > maxByWidth) {
      maxColumns = maxByWidth;
    }
    if (minColumns > maxColumns) {
      minColumns = maxColumns;
    }

    final selectedColumns = _previewColumns.clamp(minColumns, maxColumns);
    final divisions = maxColumns - minColumns;

    Widget categoryButton(PhotoCategory cat, String label, int count) {
      final selected = _selectedCategory == cat;
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.zero,
        onTap: () => _selectCategory(cat),
        leading: Icon(
          cat == PhotoCategory.cirrus
              ? Icons.cloud
              : (cat == PhotoCategory.mobile
                    ? Icons.smartphone
                    : Icons.photo_library),
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: Text('$label: $count', style: theme.textTheme.titleMedium),
        trailing: selected ? const Icon(Icons.check, size: 16) : null,
      );
    }

    // For cirrus, show total from server (includes un-fetched pages)
    final cirrusDisplayCount = _cirrusInitialLoadDone
        ? _cirrusTotal
        : cirrusCount;

    final selectedLabel = switch (_selectedCategory) {
      PhotoCategory.all => 'All',
      PhotoCategory.cirrus => 'Cirrus',
      PhotoCategory.mobile => 'Mobile',
    };

    return Container(
      width: compact ? double.infinity : 280,
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: selectedColumns > minColumns
                    ? () {
                        setState(() {
                          _previewColumns = (selectedColumns - 1).clamp(
                            minColumns,
                            maxColumns,
                          );
                        });
                      }
                    : null,
                icon: const Icon(Icons.crop_square_outlined),
                tooltip: 'Larger photos',
              ),
              Expanded(
                child: Slider(
                  min: minColumns.toDouble(),
                  max: maxColumns.toDouble(),
                  divisions: divisions > 0 ? divisions : null,
                  value: selectedColumns.toDouble(),
                  onChanged: (value) {
                    setState(() {
                      _previewColumns = value.round();
                    });
                  },
                ),
              ),
              IconButton(
                onPressed: selectedColumns < maxColumns
                    ? () {
                        setState(() {
                          _previewColumns = (selectedColumns + 1).clamp(
                            minColumns,
                            maxColumns,
                          );
                        });
                      }
                    : null,
                icon: const Icon(Icons.grid_view_outlined),
                tooltip: 'Smaller photos',
              ),
            ],
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Showing'),
              subtitle: Text(
                '$selectedLabel: ${switch (_selectedCategory) {
                  PhotoCategory.all => cirrusDisplayCount + mobileCount,
                  PhotoCategory.cirrus => cirrusDisplayCount,
                  PhotoCategory.mobile => mobileCount,
                }}',
              ),
              trailing: Icon(
                _categoriesExpanded ? Icons.expand_less : Icons.expand_more,
              ),
              onTap: () {
                setState(() {
                  _categoriesExpanded = !_categoriesExpanded;
                });
              },
            ),
            if (_categoriesExpanded) ...[
              categoryButton(
                PhotoCategory.all,
                'All',
                cirrusDisplayCount + mobileCount,
              ),
              categoryButton(
                PhotoCategory.cirrus,
                'Cirrus',
                cirrusDisplayCount,
              ),
              categoryButton(PhotoCategory.mobile, 'Mobile', mobileCount),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoGrid(List<PhotoItem> photos, int crossAxisCount) {
    // When viewing cirrus (or all), we may have more pages to load.
    // Show an extra item as a loading indicator if there are more.
    final showLoadingIndicator =
        _hasMoreCirrus &&
        (_selectedCategory == PhotoCategory.cirrus ||
            _selectedCategory == PhotoCategory.all);
    final itemCount = photos.length + (showLoadingIndicator ? 1 : 0);

    return RefreshIndicator(
      onRefresh: manualRefresh,
      child: photos.isEmpty && !_isLoadingMoreCirrus
          ? const EmptyStateWidget(
              icon: Icons.photo_library_outlined,
              headline: 'No photos yet',
              subtext: 'Photos you upload to AutoButler will appear here.',
            )
          : GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(2),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: itemCount,
              itemBuilder: (context, idx) {
                // Loading indicator in the last slot
                if (idx >= photos.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                final p = photos[idx];

                if (p.isCirrus) {
                  final c = p.cirrus!;
                  final url = CirrusService.constructThumbnailUrl(
                    c.apiPath,
                    serial: c.deviceSerial,
                  );
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () async {
                        final navigator = Navigator.of(context);
                        final bytes = await CirrusService.downloadFileBytes(
                          c.apiPath,
                          serial: c.deviceSerial,
                        );
                        if (bytes == null) return;
                        if (!mounted) return;
                        await navigator.push(
                          MaterialPageRoute(
                            builder: (_) => ImageViewerPage(
                              bytes: bytes,
                              name: c.name,
                              initialIndex: idx,
                              imageCount: photos.length,
                              getImageCount: () async =>
                                  (await _photosForCategory(
                                    _selectedCategory,
                                  )).length,
                              onLoadImage: (newIdx) async {
                                final live = await _photosForCategory(
                                  _selectedCategory,
                                );
                                if (newIdx >= live.length) return (null, '');
                                final item = live[newIdx];
                                if (item.isCirrus) {
                                  final nc = item.cirrus!;
                                  var b = await CirrusService.downloadFileBytes(
                                    nc.apiPath,
                                    serial: nc.deviceSerial,
                                  );
                                  if (b == null) {
                                    await manualRefresh();
                                  }
                                  return (b, nc.name);
                                } else {
                                  final na = item.asset!;
                                  final b = await na.originBytes;
                                  if (b == null) await manualRefresh();
                                  return (b, na.id);
                                }
                              },
                            ),
                          ),
                        );
                      },
                      child: Image.network(
                        url.toString(),
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(color: Colors.grey[300]);
                        },
                        errorBuilder: (context, error, stack) =>
                            Container(color: Colors.grey[300]),
                      ),
                    ),
                  );
                }

                // Mobile asset
                final a = p.asset!;
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () async {
                      final navigator = Navigator.of(context);
                      final bytes = await a.originBytes;
                      if (bytes == null) return;
                      if (!mounted) return;
                      await navigator.push(
                        MaterialPageRoute(
                          builder: (_) => ImageViewerPage(
                            bytes: bytes,
                            name: a.id,
                            initialIndex: idx,
                            imageCount: photos.length,
                            getImageCount: () async =>
                                (await _photosForCategory(
                                  _selectedCategory,
                                )).length,
                            onLoadImage: (newIdx) async {
                              final live = await _photosForCategory(
                                _selectedCategory,
                              );
                              if (newIdx >= live.length) return (null, '');
                              final item = live[newIdx];
                              if (item.isCirrus) {
                                final nc = item.cirrus!;
                                var b = await CirrusService.downloadFileBytes(
                                  nc.apiPath,
                                  serial: nc.deviceSerial,
                                );
                                if (b == null) await manualRefresh();
                                return (b, nc.name);
                              } else {
                                final na = item.asset!;
                                final b = await na.originBytes;
                                if (b == null) await manualRefresh();
                                return (b, na.id);
                              }
                            },
                          ),
                        ),
                      );
                    },
                    child: FutureBuilder<Uint8List?>(
                      future: a.thumbnailDataWithSize(ThumbnailSize(200, 200)),
                      builder: (context, snap) {
                        final thumb = snap.data;
                        if (thumb == null) {
                          return Container(color: Colors.grey[300]);
                        }
                        return Image.memory(thumb, fit: BoxFit.cover);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AutobutlerAppBar(
        label: 'Photos',
        icon: Icons.photo_library_outlined,
        actions: [
          RefreshIconButton(
            isRefreshing: isRefreshing,
            onPressed: manualRefresh,
            tooltip: 'Reload photos',
          ),
        ],
      ),
      drawer: AutobutlerDrawer(
        activeSection: AutobutlerDrawerSection.photos,
        onTapCirrus: () {
          context.go(AppRoutes.cirrus);
        },
        onTapPhotos: () {
          Navigator.of(context).pop();
        },
        onTapDevices: () {
          context.go(AppRoutes.devices);
        },
        onTapHealth: () {
          context.go(AppRoutes.health);
        },
        onTapSettings: () {
          context.go(AppRoutes.settings);
        },
        onTapPlugins: () {
          context.go(AppRoutes.plugins);
        },
      ),
      body: FutureBuilder<List<PhotoItem>>(
        future: _photosFuture,
        builder: (context, snapshot) {
          final photos = snapshot.data ?? const <PhotoItem>[];

          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
              final contentWidth = compact
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 281)
                        .clamp(1.0, double.infinity)
                        .toDouble();
              final crossAxisCount = _effectiveCrossAxisCount(contentWidth);

              final sidebar = _buildSidebar(
                context,
                contentWidth,
                _cirrusPhotos.length,
                _mobilePhotos.length,
                compact: compact,
              );

              Widget buildShell(Widget content) {
                if (compact) {
                  return Column(
                    children: [
                      sidebar,
                      const Divider(height: 1),
                      Expanded(child: content),
                    ],
                  );
                }

                return Row(
                  children: [
                    sidebar,
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting &&
                  photos.isEmpty) {
                return buildShell(
                  const Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                return buildShell(
                  const Center(child: Text('Failed to load photos')),
                );
              }

              return buildShell(_buildPhotoGrid(photos, crossAxisCount));
            },
          );
        },
      ),
    );
  }
}

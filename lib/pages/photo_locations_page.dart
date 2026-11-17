import 'package:flutter_map/flutter_map.dart' show MapCachingProvider;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/photo_locations_controller.dart';
import 'package:quark/models/photo_locations.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/photo_map_config.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/photo_locations/location_cluster_list.dart';
import 'package:quark/widgets/photo_locations/location_photos_pane.dart';
import 'package:quark/widgets/photo_locations/locations_summary.dart';
import 'package:quark/widgets/photo_locations/photo_locations_layout.dart';
import 'package:quark/widgets/photo_locations/photo_locations_map.dart';
import 'package:quark/widgets/photos/album_picker_sheet.dart';
import 'package:quark/widgets/photos/photo_thumbnail.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Locations view (#3557): where the household's photos were taken, on a
/// map, from the GPS position each photo's own EXIF holds and nothing else.
/// A drill-down from Photos at `/photos/locations`, so it has a back button
/// rather than the drawer.
///
/// Choosing a marker, or a row of the List alternative, opens exactly that
/// cluster's photos: a pane beside the map on a wide screen, a bottom sheet
/// on a phone. They open in the usual viewer, and a selection goes into an
/// album through the usual album flow. Nothing is copied or created by
/// looking. With the photo map turned off in Settings only the list shows,
/// and no map tile is fetched.
///
/// [focus] opens the map zoomed in there, as the viewer's map preview does.
/// It travels as the route's `extra`, never in the URL, so no position ends
/// up in an address bar, a history entry or a Referer.
class PhotoLocationsPage extends StatefulWidget {
  /// Creates the page.
  const PhotoLocationsPage({
    super.key,
    this.focus,
    this.controller,
    this.httpClient,
    this.cachingProvider,
  });

  /// Where to center the map, or null for the whole world.
  final LatLng? focus;

  /// Overrides the controller, for a test. Null uses the real services.
  final PhotoLocationsController? controller;

  /// Overrides the tile client and cache, for a test to record requests.
  final http.Client? httpClient;
  final MapCachingProvider? cachingProvider;

  @override
  State<PhotoLocationsPage> createState() => _PhotoLocationsPageState();
}

class _PhotoLocationsPageState extends State<PhotoLocationsPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final PhotoLocationsController _controller =
      widget.controller ?? PhotoLocationsController();
  final _settings = AppSettings.instance;

  @override
  Future<void> refresh() => _controller.load();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _openPhoto(int index) {
    final point = _controller.pointAt(index);
    context.push(
      AppRoutes.viewFilePath(
        point.relPath,
        serial: point.serial,
        from: AppRoutes.photoLocations,
      ),
    );
  }

  Future<void> _addSelectedToAlbum() async {
    final album = await AlbumPickerSheetHost.show(
      context,
      selectedCount: _controller.selectedIds.length,
      loadAlbums: _controller.fetchAlbums,
    );
    if (album == null || !mounted) return;
    final outcome = await _controller.addSelectedToAlbum(album.id);
    if (!mounted) return;
    final added = outcome.added;
    showMessage(
      context,
      added > 0
          ? '$added ${added == 1 ? 'photo' : 'photos'} added to "${album.name}"'
          : outcome.alreadyIn > 0 && outcome.failed == 0
          ? 'Already in "${album.name}"'
          : Errors.message(outcome.error, 'add photos to "${album.name}"'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _controller,
        _settings.photoMapEnabled,
        _settings.photoMapTiles,
        _settings.photoMapCustomTileUrl,
      ]),
      builder: (context, _) {
        final c = _controller;
        final mapEnabled = _settings.photoMapEnabled.value;
        final showMap = mapEnabled && c.view == LocationsView.map;
        final selected = c.selected;
        final error = c.error;
        Widget thumbnail(BuildContext context, PhotoLocationPoint point) =>
            PhotoThumbnail(
              url: c.thumbnailUrl(point),
              path: point.relPath,
              serial: point.serial,
            );
        return Scaffold(
          key: const ValueKey('photo_locations_page'),
          appBar: ChromeAppBar(
            title: const Text('Locations'),
            actions: [
              if (mapEnabled)
                QuarkBarSegmentedToggle(
                  key: const ValueKey('photo_locations_view'),
                  segments: const [
                    QuarkBarSegment(
                      id: 'map',
                      icon: QuarkIcons.map,
                      label: 'Map',
                    ),
                    QuarkBarSegment(
                      id: 'list',
                      icon: QuarkIcons.view_list_rounded,
                      label: 'List',
                    ),
                  ],
                  selectedId: c.view.name,
                  onSelected: (id) =>
                      c.setView(LocationsView.values.byName(id)),
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: !c.loaded
                    ? const Center(child: QuarkLoader())
                    : error != null && c.locations.points.isEmpty
                    ? EmptyStateWidget(
                        icon: QuarkIcons.location_on_outlined,
                        headline: Errors.message(
                          error,
                          'load where your photos were taken',
                        ),
                        action: OutlinedButton(
                          onPressed: manualRefresh,
                          child: const Text('Try again'),
                        ),
                      )
                    : c.locations.points.isEmpty
                    ? const EmptyStateWidget(
                        icon: QuarkIcons.location_on_outlined,
                        headline: 'No photos with a location yet',
                        subtext:
                            'A photo appears here when the camera saved where '
                            'it was taken.',
                      )
                    : PhotoLocationsLayout(
                        onClosePane: c.closeSelection,
                        map: showMap
                            ? PhotoLocationsMap(
                                clusters: c.clusters,
                                tiles: _settings.photoMapTiles.value,
                                customTileUrl:
                                    _settings.photoMapCustomTileUrl.value,
                                thumbnailBuilder: thumbnail,
                                onZoomChanged: c.setZoom,
                                onClusterTap: c.select,
                                selectedId: selected?.id,
                                initialCenter: widget.focus,
                                initialZoom: widget.focus == null
                                    ? PhotoMapConfig.initialZoom
                                    : PhotoMapConfig.photoZoom,
                                httpClient: widget.httpClient,
                                cachingProvider: widget.cachingProvider,
                              )
                            : LocationClusterList(
                                clusters: c.listClusters,
                                thumbnailBuilder: thumbnail,
                                onSelected: c.select,
                                selectedId: selected?.id,
                              ),
                        pane: selected == null
                            ? null
                            : (scrollController) => LocationPhotosPane(
                                cluster: selected,
                                photos: c.selectedPhotos,
                                selectedIds: c.selectedIds,
                                scrollController: scrollController,
                                thumbnailBuilder: (context, photo) =>
                                    thumbnail(context, c.pointFor(photo.id)!),
                                onOpen: _openPhoto,
                                onToggleSelection: c.toggleSelection,
                                onClose: c.closeSelection,
                                onAddToAlbum: _addSelectedToAlbum,
                              ),
                      ),
              ),
              LocationsSummary(locations: c.locations),
            ],
          ),
        );
      },
    );
  }
}

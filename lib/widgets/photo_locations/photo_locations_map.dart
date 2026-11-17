import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_locations.dart';
import 'package:quark/models/photo_map_tiles.dart';
import 'package:quark/utils/location_clusters.dart';
import 'package:quark/utils/photo_map_config.dart';
import 'package:quark/widgets/photo_locations/location_cluster_marker.dart';
import 'package:quark/widgets/photo_locations/photo_map_attribution.dart';
import 'package:quark/widgets/photo_locations/photo_map_tile_layer.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Locations view's map (#3557): [clusters] as thumbnail markers over
/// the tiles [tiles] names, with the OpenStreetMap attribution always on
/// screen and zoom buttons in the corner.
///
/// The parent clusters for the zoom it hears from [onZoomChanged], so
/// markers merge as the map zooms out and split as it zooms in. Scroll
/// wheel, trackpad and pinch zoom; with the map focused `+` and `-` zoom and
/// the arrow keys pan, and Tab moves on through the markers and out of the
/// map, which never traps focus. Tapping a marker opens its photos; a double
/// tap zooms into it.
///
/// Keys: `photo_map`, `photo_map_zoom_in`, `photo_map_zoom_out`, and each
/// marker's `location_cluster_<id>`.
class PhotoLocationsMap extends StatefulWidget {
  /// Creates the map.
  const PhotoLocationsMap({
    required this.clusters,
    required this.tiles,
    required this.thumbnailBuilder,
    required this.onZoomChanged,
    required this.onClusterTap,
    this.customTileUrl = '',
    this.selectedId,
    this.initialCenter,
    this.initialZoom = PhotoMapConfig.initialZoom,
    this.httpClient,
    this.cachingProvider,
    super.key,
  });

  /// The markers to draw, clustered for the map's current zoom.
  final List<LocationCluster> clusters;

  /// Where the tiles come from, and the household server's URL template.
  final PhotoMapTiles tiles;
  final String customTileUrl;

  /// A cover photo's picture.
  final Widget Function(BuildContext context, PhotoLocationPoint point)
  thumbnailBuilder;

  /// Called with the whole zoom level whenever it changes, and once with the
  /// initial one.
  final ValueChanged<int> onZoomChanged;

  /// Called when a marker is chosen.
  final ValueChanged<LocationCluster> onClusterTap;

  /// The id of the cluster whose photos are showing, drawn selected.
  final String? selectedId;

  /// Where the map opens; null opens on the whole world.
  final LatLng? initialCenter;
  final double initialZoom;

  /// Passed to the tile layer, for a test to record requests.
  final http.Client? httpClient;
  final MapCachingProvider? cachingProvider;

  @override
  State<PhotoLocationsMap> createState() => _PhotoLocationsMapState();
}

class _PhotoLocationsMapState extends State<PhotoLocationsMap> {
  final _map = MapController();
  late int _zoom = widget.initialZoom.floor();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onZoomChanged(_zoom);
    });
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool _) {
    final zoom = camera.zoom.floor();
    if (zoom == _zoom) return;
    _zoom = zoom;
    widget.onZoomChanged(zoom);
  }

  void _zoomBy(double delta) {
    final camera = _map.camera;
    _map.move(
      camera.center,
      (camera.zoom + delta).clamp(
        PhotoMapConfig.minZoom,
        PhotoMapConfig.maxZoom,
      ),
    );
  }

  void _panBy(double dx, double dy) {
    final camera = _map.camera;
    final offset = camera.latLngToScreenOffset(camera.center);
    _map.move(
      camera.screenOffsetToLatLng(offset + Offset(dx, dy)),
      camera.zoom,
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    const step = PhotoMapConfig.keyboardPanPixels;
    final key = event.logicalKey;
    final character = event.character;
    if (character == '+' ||
        character == '=' ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(1);
    } else if (character == '-' || key == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(-1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _panBy(-step, 0);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _panBy(step, 0);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _panBy(0, -step);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _panBy(0, step);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    const size = PhotoMapConfig.markerSize;
    return Focus(
      key: const ValueKey('photo_map'),
      onKeyEvent: _onKey,
      child: Semantics(
        label: 'Map of where your photos were taken',
        container: true,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: widget.initialCenter ?? const LatLng(20, 0),
                initialZoom: widget.initialZoom,
                minZoom: PhotoMapConfig.minZoom,
                maxZoom: PhotoMapConfig.maxZoom,
                backgroundColor: tokens.background,
                onPositionChanged: _onPositionChanged,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                PhotoMapTileLayer(
                  tiles: widget.tiles,
                  customUrl: widget.customTileUrl,
                  httpClient: widget.httpClient,
                  cachingProvider: widget.cachingProvider,
                ),
                MarkerLayer(
                  markers: [
                    for (final cluster in widget.clusters)
                      Marker(
                        key: ValueKey('marker_${cluster.id}'),
                        point: LatLng(cluster.latitude, cluster.longitude),
                        width: size,
                        height: size,
                        child: LocationClusterMarker(
                          cluster: cluster,
                          selected: cluster.id == widget.selectedId,
                          thumbnail: widget.thumbnailBuilder(
                            context,
                            cluster.cover,
                          ),
                          onTap: () => widget.onClusterTap(cluster),
                          onDoubleTap: () => _map.move(
                            LatLng(cluster.latitude, cluster.longitude),
                            math.min(
                              _map.camera.zoom + 2,
                              PhotoMapConfig.maxZoom,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const PhotoMapAttribution(),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(tokens.spacingSm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QuarkBarIconButton(
                      key: const ValueKey('photo_map_zoom_in'),
                      icon: QuarkIcons.add,
                      tooltip: 'Zoom in',
                      onPressed: () => _zoomBy(1),
                    ),
                    SizedBox(height: tokens.spacingXs),
                    QuarkBarIconButton(
                      key: const ValueKey('photo_map_zoom_out'),
                      icon: QuarkIcons.remove,
                      tooltip: 'Zoom out',
                      onPressed: () => _zoomBy(-1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

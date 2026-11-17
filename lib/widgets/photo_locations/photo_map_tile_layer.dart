import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_map_tiles.dart';
import 'package:quark/services/photo_locations_service.dart';
import 'package:quark/utils/photo_map_config.dart';

/// The photo map's tiles (#3557), from wherever [tiles] says: the Quark's
/// own offline pack by default, OpenStreetMap's public servers only when the
/// user opted in, or the household's own tile server at [customUrl].
///
/// Each request names only a tile, `z/x/y`, so a tile server learns which
/// area is on screen and nothing else: no photo's position is ever part of
/// a tile URL, a header or a query. The Quark's session headers go only to
/// the Quark, on the app's own client. Only the tiles the viewport needs
/// are fetched, nothing ahead of it, and flutter_map's own cache keeps
/// those a while. A custom source with no URL yet draws no tiles at all.
class PhotoMapTileLayer extends StatefulWidget {
  /// Creates the layer.
  const PhotoMapTileLayer({
    required this.tiles,
    this.customUrl = '',
    this.httpClient,
    this.cachingProvider,
    super.key,
  });

  /// Where the tiles come from.
  final PhotoMapTiles tiles;

  /// The `{z}/{x}/{y}` URL template of the household's tile server, for
  /// [PhotoMapTiles.custom].
  final String customUrl;

  /// The client tile requests go out on. Null uses the app's own client for
  /// the Quark's tiles and a fresh one for any other server; a test passes a
  /// recording one.
  final http.Client? httpClient;

  /// The tile cache; null keeps flutter_map's built-in one. A test passes
  /// `DisabledMapCachingProvider`.
  final MapCachingProvider? cachingProvider;

  /// The client and cache every layer built without its own uses, for a test
  /// of a screen that draws a map deep inside it, such as the viewer's info
  /// panel.
  @visibleForTesting
  static http.Client? debugHttpClient;
  @visibleForTesting
  static MapCachingProvider? debugCachingProvider;

  @override
  State<PhotoMapTileLayer> createState() => _PhotoMapTileLayerState();
}

class _PhotoMapTileLayerState extends State<PhotoMapTileLayer> {
  late String _url;
  late NetworkTileProvider _provider;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(PhotoMapTileLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tiles != widget.tiles ||
        oldWidget.customUrl != widget.customUrl ||
        oldWidget.httpClient != widget.httpClient) {
      // The old TileLayer disposes the old provider as it unmounts: its key
      // is the old URL.
      _build();
    }
  }

  void _build() {
    final quark = widget.tiles == PhotoMapTiles.quark;
    _url = switch (widget.tiles) {
      PhotoMapTiles.quark => PhotoLocationsService.quarkTileUrlTemplate(),
      PhotoMapTiles.openStreetMap => PhotoMapConfig.openStreetMapTiles,
      PhotoMapTiles.custom => widget.customUrl.trim(),
    };
    _provider = NetworkTileProvider(
      headers: quark ? PhotoLocationsService.quarkTileHeaders() : null,
      httpClient:
          widget.httpClient ??
          PhotoMapTileLayer.debugHttpClient ??
          (quark ? PhotoLocationsService.instance.httpClient : null),
      silenceExceptions: true,
      cachingProvider:
          widget.cachingProvider ?? PhotoMapTileLayer.debugCachingProvider,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_url.isEmpty) return const SizedBox.shrink();
    return TileLayer(
      key: ValueKey(_url),
      urlTemplate: _url,
      userAgentPackageName: PhotoMapConfig.userAgentPackageName,
      maxNativeZoom: 19,
      // Only what is on screen, and no ring of tiles around it.
      panBuffer: 0,
      tileProvider: _provider,
    );
  }
}

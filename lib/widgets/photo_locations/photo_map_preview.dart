import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_map_tiles.dart';
import 'package:quark/utils/photo_map_config.dart';
import 'package:quark/widgets/photo_locations/photo_map_attribution.dart';
import 'package:quark/widgets/photo_locations/photo_map_tile_layer.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A small, still map of where one photo was taken, for the viewer's info
/// panel (#3557). It draws from the same tile source as the Locations view,
/// so its requests name only the tiles around the photo, never the position
/// itself, unlike the "Open in Maps" link, which hands the position to a maps
/// site only when the user taps it. Tapping the preview calls [onOpen],
/// which opens the Locations view centered there. The attribution is on it
/// too.
///
/// Keyed `photo_map_preview`.
class PhotoMapPreview extends StatelessWidget {
  /// Creates the preview of [latitude], [longitude].
  const PhotoMapPreview({
    required this.latitude,
    required this.longitude,
    required this.tiles,
    required this.onOpen,
    this.customTileUrl = '',
    this.httpClient,
    this.cachingProvider,
    super.key,
  });

  /// Where the photo was taken.
  final double latitude;
  final double longitude;

  /// Where the tiles come from, and the household server's URL template.
  final PhotoMapTiles tiles;
  final String customTileUrl;

  /// Opens the Locations view centered on the photo.
  final VoidCallback onOpen;

  /// Passed to the tile layer, for a test to record requests.
  final http.Client? httpClient;
  final MapCachingProvider? cachingProvider;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final center = LatLng(latitude, longitude);
    return SizedBox(
      key: const ValueKey('photo_map_preview'),
      height: PhotoMapConfig.previewHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        child: Stack(
          children: [
            ExcludeSemantics(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: PhotoMapConfig.previewZoom,
                  backgroundColor: tokens.background,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  PhotoMapTileLayer(
                    tiles: tiles,
                    customUrl: customTileUrl,
                    httpClient: httpClient,
                    cachingProvider: cachingProvider,
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: center,
                        width: 32,
                        height: 32,
                        alignment: Alignment.topCenter,
                        child: Icon(
                          QuarkIcons.location_on,
                          color: tokens.primary,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: Semantics(
                button: true,
                label: 'Show on the Locations map',
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const ValueKey('photo_map_preview_open'),
                    onTap: onOpen,
                  ),
                ),
              ),
            ),
            const PhotoMapAttribution(),
          ],
        ),
      ),
    );
  }
}

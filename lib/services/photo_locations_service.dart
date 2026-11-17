import 'dart:convert';

import 'package:quark/models/photo_locations.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The Locations view's calls to the Quark (#3557): where the account's
/// photos were taken, and the Quark's own map tiles. Neither request carries
/// a photo's position: the points come back from the Quark, and a tile is
/// named only by its zoom, column and row.
class PhotoLocationsService with AuthenticatedService {
  PhotoLocationsService._();

  /// The shared instance, which carries the session.
  static final PhotoLocationsService instance = PhotoLocationsService._();

  /// Every photo the account can read that has a GPS position, and the
  /// library's counts.
  ///
  /// api: GET /api/v0/photos/locations
  static Future<PhotoLocations> fetch() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/photos/locations'),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to list locations');
    }
    return PhotoLocations.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// The URL template of the Quark's offline tile pack, in flutter_map's
  /// `{z}/{x}/{y}` form.
  ///
  /// api: GET /api/v0/photos/map-tiles/{z}/{x}/{y}
  static String quarkTileUrlTemplate() =>
      '${apiBaseUri.resolve('/api/v0/photos/map-tiles/')}{z}/{x}/{y}';

  /// The session headers a request for one of the Quark's own tiles
  /// carries. Never sent to any other tile server.
  static Map<String, String> quarkTileHeaders() => instance.authHeaders;
}

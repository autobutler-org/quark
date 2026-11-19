import 'dart:convert';

import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/models/album_export.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// Calls `/api/v0/albums`: listing, creating, renaming, moving and deleting photo albums, adding photos to
/// them or removing them, and exporting albums or the library as copied files.
///
/// Every change that goes through drops what it made wrong in [AlbumsCache], so no caller has to (#1779).
class AlbumService with AuthenticatedService {
  static final AlbumService _instance = AlbumService._();
  AlbumService._();
  static AlbumService get instance => _instance;

  /// api: none
  static Uri _apiUri(String path) => apiBaseUri.replace(path: '/api/v0$path');

  /// api: GET /api/v0/albums
  static Future<List<PhotoAlbum>> listAlbums({bool tree = false}) async {
    final uri = _apiUri(
      '/albums',
    ).replace(queryParameters: tree ? {'tree': 'true'} : null);
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to load albums');
    }
    final List<dynamic> data = json.decode(response.body) as List<dynamic>;
    return data
        .map((e) => PhotoAlbum.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// api: POST /api/v0/albums
  static Future<PhotoAlbum> createAlbum(String name, {int? parentId}) async {
    final body = <String, dynamic>{'name': name};
    if (parentId != null) body['parentId'] = parentId;
    final response = await instance.authenticatedPost(
      _apiUri('/albums'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode == 400 && name.contains('/')) {
      // A slash is the one 400 a name can earn; say so, not "Couldn't...".
      throw const MessageException(Errors.albumNameHasSlash);
    }
    if (response.statusCode != 201) {
      throw ApiException(response.statusCode, 'Failed to create album');
    }
    AlbumsCache.instance.dropAlbums();
    return PhotoAlbum.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  /// api: PATCH /api/v0/albums/{id}/rename
  static Future<PhotoAlbum> renameAlbum(int id, String name) async {
    final response = await instance.authenticatedPatch(
      _apiUri('/albums/$id/rename'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name}),
    );
    if (response.statusCode == 400 && name.contains('/')) {
      // A slash is the one 400 a name can earn; say so, not "Couldn't...".
      throw const MessageException(Errors.albumNameHasSlash);
    }
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to rename album');
    }
    AlbumsCache.instance.dropAlbums();
    return PhotoAlbum.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  /// api: DELETE /api/v0/albums/{id}
  static Future<void> deleteAlbum(int id) async {
    final response = await instance.authenticatedDelete(_apiUri('/albums/$id'));
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, 'Failed to delete album');
    }
    AlbumsCache.instance
      ..dropAlbums()
      ..dropItems(id);
  }

  /// api: GET /api/v0/albums/{id}/items
  static Future<List<PhotoAlbumItem>> listAlbumItems(
    int albumId, {
    PhotoSortField sort = PhotoSortField.added,
    PhotoSortOrder order = PhotoSortOrder.desc,
  }) async {
    final response = await instance.authenticatedGet(
      _apiUri('/albums/$albumId/items').replace(
        queryParameters: {'sort': sort.apiValue, 'order': order.apiValue},
      ),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to load album items');
    }
    final List<dynamic> data = json.decode(response.body) as List<dynamic>;
    return data
        .map((e) => PhotoAlbumItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Adds the photo at [relPath] on [deviceSerial] to [albumId]. Answers
  /// whether it was new to the album: the Quark answers 200 for a photo
  /// already in it, which changes nothing (#3361).
  ///
  /// api: POST /api/v0/albums/{id}/items
  static Future<bool> addPhotoToAlbum(
    int albumId, {
    required String deviceSerial,
    required String relPath,
  }) async {
    final response = await instance.authenticatedPost(
      _apiUri('/albums/$albumId/items'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'deviceSerial': deviceSerial, 'relPath': relPath}),
    );
    if (response.statusCode == 200) return false;
    if (response.statusCode != 201) {
      throw ApiException(response.statusCode, 'Failed to add photo to album');
    }
    // The tree carries the album's count, which is now one short.
    AlbumsCache.instance
      ..dropAlbums()
      ..dropItems(albumId);
    return true;
  }

  /// api: DELETE /api/v0/albums/{id}/items
  static Future<void> removePhotoFromAlbum(
    int albumId, {
    required String deviceSerial,
    required String relPath,
  }) async {
    final response = await instance.authenticatedDelete(
      _apiUri('/albums/$albumId/items'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'deviceSerial': deviceSerial, 'relPath': relPath}),
    );
    if (response.statusCode != 204) {
      throw ApiException(
        response.statusCode,
        'Failed to remove photo from album',
      );
    }
    AlbumsCache.instance
      ..dropAlbums()
      ..dropItems(albumId);
  }

  /// Queues an export of [albumIds], each with its sub-albums, or of the
  /// whole library when [library] is true, into a new folder the Quark makes
  /// inside [folder] on the drive [deviceSerial] (empty is the internal
  /// drive). Nothing in the library or the albums changes (#3501).
  ///
  /// Throws an [ApiException] when the Quark refuses: 400 when nothing was
  /// chosen, 403 when the account can't add files to [folder], 404 when an
  /// album or the folder is not there.
  ///
  /// api: POST /api/v0/albums/exports
  static Future<QueuedAlbumExport> startExport({
    List<int> albumIds = const [],
    bool library = false,
    required String deviceSerial,
    required String folder,
  }) async {
    final response = await instance.authenticatedPost(
      _apiUri('/albums/exports'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'albumIds': library ? const <int>[] : albumIds,
        'library': library,
        'deviceSerial': deviceSerial,
        'folder': folder,
      }),
    );
    if (response.statusCode != 202) {
      throw ApiException(response.statusCode, 'Failed to start photo export');
    }
    return QueuedAlbumExport.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  /// What export job [jobId] has copied and which photos it could not.
  ///
  /// api: GET /api/v0/albums/exports/{jobId}
  static Future<AlbumExportSummary> exportSummary(int jobId) async {
    final response = await instance.authenticatedGet(
      _apiUri('/albums/exports/$jobId'),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to load photo export');
    }
    return AlbumExportSummary.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }
}

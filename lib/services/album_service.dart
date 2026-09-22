import 'dart:convert';

import 'package:quark/models/photo_album.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// Calls `/api/v0/albums`: listing, creating, renaming, moving and deleting photo albums, and adding photos to
/// them or removing them.
class AlbumService with AuthenticatedService {
  static final AlbumService _instance = AlbumService._();
  AlbumService._();
  static AlbumService get instance => _instance;

  static Uri _apiUri(String path) => apiBaseUri.replace(path: '/api/v0$path');

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
    return PhotoAlbum.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

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
    return PhotoAlbum.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<PhotoAlbum> moveAlbum(int id, {int? parentId}) async {
    final response = await instance.authenticatedPatch(
      _apiUri('/albums/$id/move'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'parentId': parentId}),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to move album');
    }
    return PhotoAlbum.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> deleteAlbum(int id) async {
    final response = await instance.authenticatedDelete(_apiUri('/albums/$id'));
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, 'Failed to delete album');
    }
  }

  static Future<List<PhotoAlbumItem>> listAlbumItems(int albumId) async {
    final response = await instance.authenticatedGet(
      _apiUri('/albums/$albumId/items'),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to load album items');
    }
    final List<dynamic> data = json.decode(response.body) as List<dynamic>;
    return data
        .map((e) => PhotoAlbumItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<PhotoAlbumItem> addPhotoToAlbum(
    int albumId, {
    required String deviceSerial,
    required String relPath,
  }) async {
    final response = await instance.authenticatedPost(
      _apiUri('/albums/$albumId/items'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'deviceSerial': deviceSerial, 'relPath': relPath}),
    );
    if (response.statusCode != 201) {
      throw ApiException(response.statusCode, 'Failed to add photo to album');
    }
    return PhotoAlbumItem.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

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
  }
}

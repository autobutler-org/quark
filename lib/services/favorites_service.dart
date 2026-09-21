import 'dart:convert';

import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

class FavoriteStatus {
  final bool isFavorite;
  const FavoriteStatus({required this.isFavorite});
  factory FavoriteStatus.fromJson(Map<String, dynamic> json) =>
      FavoriteStatus(isFavorite: json['isFavorite'] as bool? ?? false);
}

/// Calls `/api/v0/favorites`: toggling a photo's favorite state, checking it, and listing favorites.
class FavoritesService with AuthenticatedService {
  static final FavoritesService _instance = FavoritesService._();
  FavoritesService._();
  static FavoritesService get instance => _instance;

  static Uri _apiUri(String path) => apiBaseUri.resolve('/api/v0$path');

  /// Toggles favorite state. Returns the new isFavorite value.
  static Future<bool> toggle({required String relPath, String? serial}) async {
    final response = await instance.authenticatedPost(
      _apiUri('/photos/favorite'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'relPath': relPath, 'deviceSerial': serial ?? ''}),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Failed to toggle favorite');
    }
    final d = json.decode(response.body) as Map<String, dynamic>;
    return d['isFavorite'] as bool? ?? false;
  }

  /// Returns all favorited photo keys in the format "deviceSerial:relPath".
  static Future<Set<String>> listFavoriteKeys() async {
    final uri = _apiUri('/photos/favorites');
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode != 200) return {};
    final list = json.decode(response.body) as List<dynamic>;
    return list.map((item) {
      final m = item as Map<String, dynamic>;
      final serial = m['deviceSerial'] as String? ?? '';
      final relPath = m['relPath'] as String? ?? '';
      return '$serial:$relPath';
    }).toSet();
  }

  /// Returns whether a photo is favorited.
  static Future<bool> isFavorite({
    required String relPath,
    String? serial,
  }) async {
    final uri = _apiUri('/photos/favorite').replace(
      queryParameters: {
        'relPath': relPath,
        if (serial != null && serial.isNotEmpty) 'serial': serial,
      },
    );
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode != 200) return false;
    final d = json.decode(response.body) as Map<String, dynamic>;
    return d['isFavorite'] as bool? ?? false;
  }
}

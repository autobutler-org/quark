import 'dart:convert';

import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Calls `/api/v0/previews`, the read-only views of office files the client
/// does not open itself (#2987).
///
/// Properties are the one call so far: `GET /previews/properties` reads the
/// small metadata entry and nothing of the body, which is cheap enough to
/// show on the generic viewer.
class PreviewsService with AuthenticatedService {
  PreviewsService._();

  /// The shared service.
  static final PreviewsService instance = PreviewsService._();

  /// Extensions `GET /previews/properties` reads. Anything else is a 400, so
  /// the viewer does not ask.
  static const propertyExtensions = {
    '.docx',
    '.docm',
    '.dotx',
    '.dotm',
    '.pptx',
    '.pptm',
    '.ppsx',
    '.potx',
    '.xlsx',
    '.xlsm',
    '.xltx',
    '.xltm',
    '.odt',
    '.ott',
    '.odp',
    '.otp',
    '.ods',
    '.ots',
    '.rtf',
  };

  /// Whether [name] is a format `GET /previews/properties` can read.
  static bool supportsProperties(String name) =>
      propertyExtensions.contains(fileExtension(name));

  /// The properties the office file at [path] saved about itself.
  ///
  /// A refused request throws an [ApiException]. A body that is not the
  /// properties object throws a [FormatException].
  static Future<DocumentProperties> properties(
    String path, {
    String? serial,
  }) async {
    final response = await instance.authenticatedGet(
      _uri('/api/v0/previews/properties', {'filePath': path, 'serial': serial}),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'load the properties');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Properties response is not an object');
    }
    return DocumentProperties.fromJson(decoded);
  }

  /// [endpoint] on the active Quark with [query], leaving out empty values.
  static Uri _uri(String endpoint, Map<String, String?> query) => apiBaseUri
      .resolve(endpoint)
      .replace(
        queryParameters: {
          for (final MapEntry(:key, :value) in query.entries)
            if (value != null && value.trim().isNotEmpty) key: value,
        },
      );
}

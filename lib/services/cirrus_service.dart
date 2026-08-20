import 'dart:convert';

import 'package:autobutler/models/cirrus_file_node.dart';
import 'package:autobutler/models/paginated_photos_response.dart';
import 'package:autobutler/models/photo_metadata.dart';
import 'package:autobutler/services/app_settings.dart';
import 'package:autobutler/services/authenticated_service.dart';
import 'package:autobutler/utils/web_download_stub.dart'
    if (dart.library.html) 'package:autobutler/utils/web_download_web.dart'
    as web_download;
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:http/http.dart' as http;

class CirrusRequestException implements Exception {
  const CirrusRequestException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class CirrusService with AuthenticatedService {
  static final CirrusService _instance = CirrusService._();
  CirrusService._();
  static CirrusService get instance => _instance;
  static Map<String, String> get _authHeaders => instance.authHeaders;

  static Uri get _apiBaseUri {
    final configured = AppSettings.instance.activeHost;
    final base =
        configured ??
        String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://localhost:8080',
        );
    final uri = Uri.parse(base);
    final isLoopbackHost =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        isLoopbackHost) {
      return uri.replace(host: '10.0.2.2');
    }

    return uri;
  }

  static String _responseMessage(
    http.Response response, {
    required String fallback,
  }) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return error;
        }
      }
    } catch (_) {
      // Fall back to the caller-provided message when the response is not JSON.
    }
    return fallback;
  }

  static Uri constructMediaUrl(String filePath, {String? serial}) {
    final querySegments = <String>[
      'filePath=${Uri.encodeQueryComponent(filePath)}',
    ];

    final serialValue = serial?.trim() ?? '';
    if (serialValue.isNotEmpty) {
      querySegments.add('serial=${Uri.encodeQueryComponent(serialValue)}');
    }
    // Include token so the browser <video> element (which cannot send custom
    // Authorization headers) can still authenticate against the download endpoint.
    final token = AppSettings.instance.sessionToken;
    if (token != null && token.isNotEmpty) {
      querySegments.add('token=${Uri.encodeQueryComponent(token)}');
    }
    final endpointUri = _apiBaseUri.resolve('/api/v0/cirrus/download');
    return endpointUri.replace(query: querySegments.join('&'));
  }

  /// Construct a URL for the thumbnail endpoint.
  /// The backend exposes thumbnails at /api/v0/thumbnails/*filePath where filePath is a
  /// path-like segment. Each path segment is percent-encoded to preserve slashes.
  static Uri constructThumbnailUrl(
    String filePath, {
    String? serial,
    String? size,
  }) {
    final trimmed = filePath.trim();
    final normalized = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    final encodedPath = normalized
        .split('/')
        .map((s) => Uri.encodeComponent(s))
        .join('/');
    final endpointUri = _apiBaseUri.resolve('/api/v0/thumbnails/$encodedPath');

    // Build query params — include token when set so Image.network() (which
    // cannot set custom headers) can still authenticate.
    final params = <String, String>{};
    final serialValue = serial?.trim() ?? '';
    if (serialValue.isNotEmpty) params['serial'] = serialValue;
    if (size != null && size.isNotEmpty) params['size'] = size;
    final token = AppSettings.instance.sessionToken;
    if (token != null && token.isNotEmpty) params['token'] = token;

    return params.isEmpty
        ? endpointUri
        : endpointUri.replace(queryParameters: params);
  }

  /// Fetches a paginated list of photos from the dedicated photos endpoint.
  /// Returns a [PaginatedPhotosResponse] with photos, total count, offset, and limit.
  static Future<PaginatedPhotosResponse> getPhotos({
    int offset = 0,
    int limit = 50,
    String? serial,
  }) async {
    final querySegments = <String>['offset=$offset', 'limit=$limit'];
    final serialValue = serial?.trim() ?? '';
    if (serialValue.isNotEmpty) {
      querySegments.add('serial=${Uri.encodeQueryComponent(serialValue)}');
    }

    final endpointUri = _apiBaseUri.resolve('/api/v0/photos');
    final uri = endpointUri.replace(query: querySegments.join('&'));

    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load photos (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected photos response format');
    }

    return PaginatedPhotosResponse.fromJson(decoded);
  }

  static Future<List<CirrusFileNode>> getFiles(
    String path, {
    List<String>? serials,
  }) async {
    final normalizedPath = _normalizePath(path);
    final serialValues =
        serials
            ?.map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];

    final querySegments = <String>[];
    if (normalizedPath.isNotEmpty) {
      querySegments.add(
        'rootDir=${Uri.encodeQueryComponent(_toRootDir(normalizedPath))}',
      );
    }
    for (final serial in serialValues) {
      querySegments.add('serial=${Uri.encodeQueryComponent(serial)}');
    }

    final endpointUri = _apiBaseUri.resolve('/api/v0/cirrus');
    final uri = querySegments.isEmpty
        ? endpointUri
        : endpointUri.replace(query: querySegments.join('&'));

    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CirrusRequestException(
        statusCode: response.statusCode,
        message: _responseMessage(
          response,
          fallback: 'Failed to load cirrus files (${response.statusCode})',
        ),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected cirrus response format');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(CirrusFileNode.fromJson)
        .toList(growable: false);
  }

  /// Returns all files of [fileType] across all devices, newest-modified first.
  /// [fileType] should be one of the server-defined type strings: 'abdoc', 'absheet', etc.
  static Future<List<CirrusFileNode>> getFilesByType(
    String fileType, {
    List<String>? serials,
  }) async {
    final querySegments = <String>[
      'fileType=${Uri.encodeQueryComponent(fileType)}',
    ];
    for (final serial in serials ?? const <String>[]) {
      if (serial.isNotEmpty) {
        querySegments.add('serial=${Uri.encodeQueryComponent(serial)}');
      }
    }
    final uri = _apiBaseUri
        .resolve('/api/v0/cirrus/by-type')
        .replace(query: querySegments.join('&'));

    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load files by type (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    // The backend always returns a JSON array (even when empty: []).
    // Guard defensively: if for any reason the response is not a list
    // (e.g. a transitional server version wrapping data in an object,
    // or an error body slipping through with a 2xx status), return []
    // rather than throwing — the UI will show the friendly empty state
    // instead of a raw exception message.
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(CirrusFileNode.fromJson)
        .toList(growable: false);
  }

  /// Returns recently modified files across all devices, newest first.
  static Future<List<CirrusFileNode>> getRecentFiles({
    int limit = 20,
    List<String>? serials,
  }) async {
    final querySegments = <String>['limit=$limit'];
    for (final serial in serials ?? const <String>[]) {
      if (serial.isNotEmpty) {
        querySegments.add('serial=${Uri.encodeQueryComponent(serial)}');
      }
    }
    final uri = _apiBaseUri
        .resolve('/api/v0/cirrus/recent')
        .replace(query: querySegments.join('&'));

    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load recent files (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected response format for recent files');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(CirrusFileNode.fromJson)
        .toList(growable: false);
  }

  static Future<List<CirrusFileNode>> searchFiles(
    String query, {
    List<String>? serials,
  }) async {
    final serialValues =
        serials
            ?.map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    final querySegments = <String>[];
    querySegments.add('query=${Uri.encodeQueryComponent(query)}');
    for (final serial in serialValues) {
      querySegments.add('serial=${Uri.encodeQueryComponent(serial)}');
    }
    final endpointUri = _apiBaseUri.resolve('/api/v0/cirrus/search');
    final uri = querySegments.isEmpty
        ? endpointUri
        : endpointUri.replace(query: querySegments.join('&'));
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load cirrus files (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected cirrus response format');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(CirrusFileNode.fromJson)
        .toList(growable: false);
  }

  /// Lists the direct children of [subPath] inside the archive at [filePath].
  /// Returns the entries as [CirrusFileNode]s with [isDir] set appropriately.
  /// No data is extracted to disk — only archive headers are read.
  static Future<List<CirrusFileNode>> listArchiveEntries(
    String filePath, {
    String subPath = '',
    String? serial,
  }) async {
    final querySegments = <String>[
      'filePath=${Uri.encodeQueryComponent(filePath)}',
    ];
    if (subPath.isNotEmpty) {
      querySegments.add('subPath=${Uri.encodeQueryComponent(subPath)}');
    }
    final serialValue = serial?.trim() ?? '';
    if (serialValue.isNotEmpty) {
      querySegments.add('serial=${Uri.encodeQueryComponent(serialValue)}');
    }
    final endpointUri = _apiBaseUri.resolve('/api/v0/cirrus/list-archive');
    final uri = endpointUri.replace(query: querySegments.join('&'));
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to list archive entries (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected archive listing response format');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(CirrusFileNode.fromJson)
        .toList(growable: false);
  }

  static Future<void> extractFile(String filePath, {String? serial}) async {
    final querySegments = <String>[
      'filePath=${Uri.encodeQueryComponent(filePath)}',
    ];
    final serialValue = serial?.trim() ?? '';
    if (serialValue.isNotEmpty) {
      querySegments.add('serial=${Uri.encodeQueryComponent(serialValue)}');
    }
    final endpointUri = _apiBaseUri.resolve('/api/v0/cirrus/extract');
    final uri = endpointUri.replace(query: querySegments.join('&'));
    final response = await instance.authenticatedPost(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to extract file (${response.statusCode})');
    }
  }

  /// Returns filesystem metadata for [filePath]: whether it is a directory
  /// and its resolved [fileType] string (e.g. "image", "abdoc", "folder").
  /// Throws if the path does not exist or the request fails.
  static Future<({bool isDir, String fileType, String name})> statFile(
    String filePath, {
    String? serial,
  }) async {
    final querySegments = <String>[
      'filePath=${Uri.encodeQueryComponent(filePath)}',
    ];
    final serialValue = serial?.trim() ?? '';
    if (serialValue.isNotEmpty) {
      querySegments.add('serial=${Uri.encodeQueryComponent(serialValue)}');
    }
    final endpointUri = _apiBaseUri.resolve('/api/v0/cirrus/stat');
    final uri = endpointUri.replace(query: querySegments.join('&'));
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CirrusRequestException(
        statusCode: response.statusCode,
        message: _responseMessage(
          response,
          fallback: 'Failed to stat file (${response.statusCode})',
        ),
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected stat response format');
    }
    return (
      isDir: decoded['isDir'] as bool? ?? false,
      fileType: decoded['fileType'] as String? ?? 'generic',
      name: decoded['name'] as String? ?? '',
    );
  }

  static Future<void> deleteFile(
    String rootDir,
    String fileName, {
    String? deviceSerial,
  }) async {
    final queryParams = <String, Object>{
      'rootDir': rootDir,
      'filePaths': fileName,
    };
    final serial = deviceSerial?.trim() ?? '';
    if (serial.isNotEmpty) {
      queryParams['serial'] = serial;
    }

    final endpointUri = _apiBaseUri.resolve('/api/v0/cirrus');
    final uri = endpointUri.replace(queryParameters: queryParams);

    final response = await instance.authenticatedDelete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to delete file (${response.statusCode})');
    }
  }

  /// Deletes multiple files/folders in a single request.
  ///
  /// All [nodes] must share the same device serial (or all belong to the
  /// internal storage). Callers are responsible for grouping nodes by serial
  /// before calling this method.
  static Future<void> deleteFiles(
    List<String> filePaths, {
    String? rootDir,
    String? deviceSerial,
  }) async {
    if (filePaths.isEmpty) return;
    // The backend accepts repeated `filePaths` query params.
    final querySegments = <String>[];
    if (rootDir != null && rootDir.isNotEmpty) {
      querySegments.add('rootDir=${Uri.encodeQueryComponent(rootDir)}');
    }
    for (final p in filePaths) {
      querySegments.add('filePaths=${Uri.encodeQueryComponent(p)}');
    }
    final serial = deviceSerial?.trim() ?? '';
    if (serial.isNotEmpty) {
      querySegments.add('serial=${Uri.encodeQueryComponent(serial)}');
    }
    final uri = _apiBaseUri
        .resolve('/api/v0/cirrus')
        .replace(query: querySegments.join('&'));
    final response = await instance.authenticatedDelete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to delete files (\${response.statusCode})');
    }
  }

  static Future<void> moveFile(
    String oldPath,
    String newPath, {
    String? oldDeviceSerial,
    String? newDeviceSerial,
  }) async {
    final endpointUri = _apiBaseUri.resolve('/api/v0/cirrus');
    final requestBody = <String, String>{
      'oldFilePath': oldPath,
      'newFilePath': newPath,
    };

    final oldSerial = oldDeviceSerial?.trim() ?? '';
    if (oldSerial.isNotEmpty) {
      requestBody['oldDeviceSerial'] = oldSerial;
    }

    final newSerial = newDeviceSerial?.trim() ?? '';
    if (newSerial.isNotEmpty) {
      requestBody['newDeviceSerial'] = newSerial;
    }

    final body = jsonEncode(requestBody);

    final response = await instance.authenticatedPut(
      endpointUri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to move file (${response.statusCode})');
    }
  }

  static Future<void> createFolder(String folderPath, String folderName) async {
    final trimmedFolderPath = folderPath.trim();
    final endpointPath = trimmedFolderPath.isEmpty
        ? '/api/v0/cirrus/folder/'
        : _joinPaths('/api/v0/cirrus/folder', trimmedFolderPath);
    final endpointUri = _apiBaseUri.resolve(endpointPath);

    final request = http.MultipartRequest('POST', endpointUri);
    request.fields['folderName'] = folderName;
    request.headers.addAll(_authHeaders);

    final response = await request.send();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to create folder (${response.statusCode})');
    }
  }

  static Future<http.StreamedResponse> uploadFilesFromFormData(
    String uploadPath,
    List<http.MultipartFile> formDataFiles, {
    String? serial,
    bool overwrite = false,
  }) async {
    final uploadEndpointPath = _joinPaths('/api/v0/cirrus/upload', uploadPath);
    final endpointUri = _apiBaseUri.resolve(uploadEndpointPath);

    final serialValue = serial?.trim() ?? '';
    final queryParams = <String, String>{
      if (serialValue.isNotEmpty) 'serial': serialValue,
      if (overwrite) 'overwrite': 'true',
    };
    final uri = queryParams.isEmpty
        ? endpointUri
        : endpointUri.replace(queryParameters: queryParams);

    final request = http.MultipartRequest('POST', uri);
    request.files.addAll(formDataFiles);
    request.headers.addAll(_authHeaders);

    final response = await request.send();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to upload files (${response.statusCode})');
    }

    return response;
  }

  static Future<String?> saveFile(
    String filePath, {
    String? serial,
    String? fileName,
  }) async {
    final uri = _buildDownloadUri(filePath, serial: serial);
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to download file (${response.statusCode})');
    }

    final resolvedName = _resolveDownloadFileName(
      response.headers['content-disposition'],
      preferredName: fileName,
      fallbackPath: filePath,
    );

    final bytes = Uint8List.fromList(response.bodyBytes);

    if (kIsWeb) {
      return web_download.saveBytesForDownload(bytes, resolvedName);
    }

    final params = SaveFileDialogParams(data: bytes, fileName: resolvedName);

    return FlutterFileDialog.saveFile(params: params);
  }

  /// Saves raw bytes to disk (or browser download) using the same logic as [saveFile].
  static Future<String?> saveBytesToFile(
    Uint8List bytes,
    String fileName,
  ) async {
    if (kIsWeb) {
      return web_download.saveBytesForDownload(bytes, fileName);
    }
    final params = SaveFileDialogParams(data: bytes, fileName: fileName);
    return FlutterFileDialog.saveFile(params: params);
  }

  /// Downloads a single file from inside an archive without extracting to disk.
  static Future<Uint8List?> downloadArchiveFileBytes(
    String archivePath,
    String entryPath, {
    String? serial,
  }) async {
    final querySegments = <String>[
      'filePath=${Uri.encodeQueryComponent(archivePath)}',
      'entryPath=${Uri.encodeQueryComponent(entryPath)}',
    ];
    final serialValue = serial?.trim() ?? '';
    if (serialValue.isNotEmpty) {
      querySegments.add('serial=${Uri.encodeQueryComponent(serialValue)}');
    }
    final endpointUri = _apiBaseUri.resolve(
      '/api/v0/cirrus/download-archive-file',
    );
    final uri = endpointUri.replace(query: querySegments.join('&'));
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to download archive file (${response.statusCode})',
      );
    }
    return response.bodyBytes;
  }

  static Future<Uint8List?> downloadFileBytes(
    String filePath, {
    String? serial,
    String? fileName,
  }) async {
    var uri = _buildDownloadUri(filePath, serial: serial);
    if (kIsWeb && _needsServerConversion(filePath)) {
      final params = Map<String, String>.from(uri.queryParameters);
      params['format'] = 'jpeg';
      uri = uri.replace(queryParameters: params);
    }
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to download file (${response.statusCode})');
    }

    return response.bodyBytes;
  }

  static bool _needsServerConversion(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.heic') ||
        lower.endsWith('.heif') ||
        lower.endsWith('.tiff') ||
        lower.endsWith('.tif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.raw') ||
        lower.endsWith('.cr2') ||
        lower.endsWith('.cr3') ||
        lower.endsWith('.nef') ||
        lower.endsWith('.arw') ||
        lower.endsWith('.dng') ||
        lower.endsWith('.orf') ||
        lower.endsWith('.rw2');
  }

  /// Download thumbnail bytes for the specified filePath using the thumbnails endpoint.
  /// Returns the raw bytes of the thumbnail image, or throws on non-success status codes.
  static Future<Uint8List?> downloadThumbnailBytes(
    String filePath, {
    String? serial,
  }) async {
    final uri = constructThumbnailUrl(filePath, serial: serial);
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to download thumbnail (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  static Future<PhotoMetadata> getPhotoMetadata(
    String relPath, {
    String? serial,
  }) async {
    final params = <String, String>{'relPath': relPath};
    final serialValue = serial?.trim() ?? '';
    if (serialValue.isNotEmpty) params['serial'] = serialValue;
    final uri = _apiBaseUri
        .resolve('/api/v0/photos/metadata')
        .replace(queryParameters: params);
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load photo metadata (${response.statusCode})');
    }
    return PhotoMetadata.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Persists [rotationQuarters] (0–3) for a photo on the server.
  /// A value of 0 removes the rotation record entirely.
  static Future<void> rotatePhoto(
    String relPath, {
    String? serial,
    required int rotationQuarters,
  }) async {
    final uri = _apiBaseUri.resolve('/api/v0/photos/rotate');
    final body = jsonEncode({
      'relPath': relPath,
      'serial': serial?.trim() ?? '',
      'rotationQuarters': rotationQuarters % 4,
    });
    final response = await instance.authenticatedPost(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to save rotation (${response.statusCode})');
    }
  }

  /// Duplicates a photo on the server. Returns the relative path of the new
  /// file (e.g. "photos/IMG_001_copy.jpg").
  static Future<String> copyPhoto(String relPath, {String? serial}) async {
    final uri = _apiBaseUri.resolve('/api/v0/photos/copy');
    final body = jsonEncode({
      'relPath': relPath,
      'serial': serial?.trim() ?? '',
    });
    final response = await instance.authenticatedPost(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to copy photo (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['relPath'] as String;
  }

  static Uri _buildDownloadUri(String filePath, {String? serial}) {
    final querySegments = <String>[
      'filePath=${Uri.encodeQueryComponent(filePath)}',
    ];

    final serialValue = serial?.trim() ?? '';
    if (serialValue.isNotEmpty) {
      querySegments.add('serial=${Uri.encodeQueryComponent(serialValue)}');
    }

    final endpointUri = _apiBaseUri.resolve('/api/v0/cirrus/download');
    return endpointUri.replace(query: querySegments.join('&'));
  }

  static String _resolveDownloadFileName(
    String? contentDisposition, {
    String? preferredName,
    required String fallbackPath,
  }) {
    final explicitName = preferredName?.trim() ?? '';
    if (explicitName.isNotEmpty) {
      return explicitName;
    }

    final extractedName = _extractFileNameFromContentDisposition(
      contentDisposition,
    );
    if (extractedName != null && extractedName.isNotEmpty) {
      return extractedName;
    }

    final normalized = fallbackPath.trim();
    if (normalized.isEmpty) {
      return 'download';
    }

    final withoutTrailing = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    if (withoutTrailing.isEmpty) {
      return 'download';
    }

    final lastSlash = withoutTrailing.lastIndexOf('/');
    if (lastSlash < 0 || lastSlash == withoutTrailing.length - 1) {
      return withoutTrailing;
    }
    return withoutTrailing.substring(lastSlash + 1);
  }

  static String? _extractFileNameFromContentDisposition(String? headerValue) {
    if (headerValue == null || headerValue.trim().isEmpty) {
      return null;
    }

    final utf8Match = RegExp(
      r"filename\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(headerValue);
    if (utf8Match != null) {
      return Uri.decodeFull(utf8Match.group(1) ?? '').replaceAll('"', '');
    }

    final basicMatch = RegExp(
      r'filename="?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(headerValue);
    if (basicMatch != null) {
      return basicMatch.group(1)?.trim();
    }

    return null;
  }

  static String _normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '';
    }

    final withLeadingSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    if (withLeadingSlash.endsWith('/') && withLeadingSlash.length > 1) {
      return withLeadingSlash.substring(0, withLeadingSlash.length - 1);
    }
    return withLeadingSlash;
  }

  static String _toRootDir(String normalizedPath) {
    if (normalizedPath.isEmpty) {
      return '';
    }
    return normalizedPath.substring(1);
  }

  static String _joinPaths(String basePath, String appendPath) {
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final normalizedAppend = appendPath.trim();

    if (normalizedAppend.isEmpty) {
      return normalizedBase;
    }

    final strippedAppend = normalizedAppend.startsWith('/')
        ? normalizedAppend.substring(1)
        : normalizedAppend;
    return '$normalizedBase/$strippedAppend';
  }

  static Future<Map<String, dynamic>> getInstalledVersion() async {
    final endpointUri = _apiBaseUri.resolve('/api/v0/version');
    final response = await instance.authenticatedGet(endpointUri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to get installed version (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Unexpected version response format');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Future<List<Map<String, dynamic>>> listAvailableVersions({
    bool all = false,
  }) async {
    final endpointUri = _apiBaseUri.resolve('/api/v0/version/available');
    final uri = all ? endpointUri.replace(query: 'all=true') : endpointUri;
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to list available versions (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected available versions response format');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  /// Extracts a still frame from a video at [timestampMs] milliseconds.
  /// Returns the relative path of the saved JPEG file.
  static Future<String> extractVideoFrame(
    String relPath, {
    String? serial,
    required int timestampMs,
  }) async {
    final uri = _apiBaseUri.resolve('/api/v0/videos/extract-frame');
    final body = jsonEncode({
      'relPath': relPath,
      'serial': serial?.trim() ?? '',
      'timestampMs': timestampMs,
    });
    final response = await instance.authenticatedPost(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to extract frame (${response.statusCode}): ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['relPath'] as String;
  }

  /// Trims [relPath] to the range [startMs, endMs] and saves a new file.
  /// Returns the relative path of the saved clip.
  static Future<String> trimVideo(
    String relPath, {
    String? serial,
    required int startMs,
    required int endMs,
  }) async {
    final uri = _apiBaseUri.resolve('/api/v0/videos/trim');
    final body = jsonEncode({
      'relPath': relPath,
      'serial': serial?.trim() ?? '',
      'startMs': startMs,
      'endMs': endMs,
    });
    final response = await instance.authenticatedPost(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to trim video (${response.statusCode}): ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['relPath'] as String;
  }

  /// Queues a background transcode job. Returns the job ID.
  static Future<int> transcodeVideo(
    String relPath, {
    String? serial,
    required String preset,
  }) async {
    final uri = _apiBaseUri.resolve('/api/v0/videos/transcode');
    final body = jsonEncode({
      'relPath': relPath,
      'serial': serial?.trim() ?? '',
      'preset': preset,
    });
    final response = await instance.authenticatedPost(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to queue transcode (${response.statusCode}): ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['jobId'] as int;
  }

  /// Gets the status of a video processing job.
  static Future<Map<String, dynamic>> getVideoJob(int jobId) async {
    final uri = _apiBaseUri.resolve('/api/v0/videos/jobs/$jobId');
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to get job $jobId (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Lists recent video processing jobs.
  static Future<List<Map<String, dynamic>>> listVideoJobs() async {
    final uri = _apiBaseUri.resolve('/api/v0/videos/jobs');
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to list video jobs (${response.statusCode})');
    }
    return (jsonDecode(response.body) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  static Future<void> updateToVersion(String version) async {
    final endpointUri = _apiBaseUri.resolve('/api/v0/version/update');
    final body = jsonEncode({'version': version});
    final response = await instance.authenticatedPost(
      endpointUri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to perform update (${response.statusCode}): ${response.body}',
      );
    }
  }
}

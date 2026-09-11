import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:quark/models/file_node.dart';
import 'package:quark/models/paginated_photos_response.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/utils/web_download_stub.dart'
    if (dart.library.html) 'package:quark/utils/web_download_web.dart'
    as web_download;

class FilesRequestException implements Exception {
  const FilesRequestException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class FilesService with AuthenticatedService {
  static final FilesService _instance = FilesService._();
  FilesService._();
  static FilesService get instance => _instance;
  static Map<String, String> get _authHeaders => instance.authHeaders;

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
    final endpointUri = apiBaseUri.resolve('/api/v0/files/download');
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
    final endpointUri = apiBaseUri.resolve('/api/v0/thumbnails/$encodedPath');

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

    final endpointUri = apiBaseUri.resolve('/api/v0/photos');
    final uri = endpointUri.replace(query: querySegments.join('&'));

    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to load photos');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected photos response format');
    }

    return PaginatedPhotosResponse.fromJson(decoded);
  }

  static Future<List<FileNode>> getFiles(
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

    final endpointUri = apiBaseUri.resolve('/api/v0/files');
    final uri = querySegments.isEmpty
        ? endpointUri
        : endpointUri.replace(query: querySegments.join('&'));

    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FilesRequestException(
        statusCode: response.statusCode,
        message: _responseMessage(
          response,
          fallback: 'Failed to load files (${response.statusCode})',
        ),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected files response format');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(FileNode.fromJson)
        .toList(growable: false);
  }

  /// Returns all files of [fileType] across all devices, newest-modified first.
  /// [fileType] should be one of the server-defined type strings: 'qdoc', 'qsheet', etc.
  static Future<List<FileNode>> getFilesByType(
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
    final uri = apiBaseUri
        .resolve('/api/v0/files/by-type')
        .replace(query: querySegments.join('&'));

    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to load files by type');
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
        .map(FileNode.fromJson)
        .toList(growable: false);
  }

  /// Returns recently modified files across all devices, newest first.
  static Future<List<FileNode>> getRecentFiles({
    int limit = 20,
    List<String>? serials,
  }) async {
    final querySegments = <String>['limit=$limit'];
    for (final serial in serials ?? const <String>[]) {
      if (serial.isNotEmpty) {
        querySegments.add('serial=${Uri.encodeQueryComponent(serial)}');
      }
    }
    final uri = apiBaseUri
        .resolve('/api/v0/files/recent')
        .replace(query: querySegments.join('&'));

    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to load recent files');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected response format for recent files');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(FileNode.fromJson)
        .toList(growable: false);
  }

  static Future<List<FileNode>> searchFiles(
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
    final endpointUri = apiBaseUri.resolve('/api/v0/files/search');
    final uri = querySegments.isEmpty
        ? endpointUri
        : endpointUri.replace(query: querySegments.join('&'));
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to load files');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected files response format');
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(FileNode.fromJson)
        .toList(growable: false);
  }

  /// Lists the direct children of [subPath] inside the archive at [filePath].
  /// Returns the entries as [FileNode]s with [isDir] set appropriately.
  /// No data is extracted to disk — only archive headers are read.
  static Future<List<FileNode>> listArchiveEntries(
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
    final endpointUri = apiBaseUri.resolve('/api/v0/files/list-archive');
    final uri = endpointUri.replace(query: querySegments.join('&'));
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to list archive entries');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected archive listing response format');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(FileNode.fromJson)
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
    final endpointUri = apiBaseUri.resolve('/api/v0/files/extract');
    final uri = endpointUri.replace(query: querySegments.join('&'));
    final response = await instance.authenticatedPost(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to extract file');
    }
  }

  /// Converts the .xlsx or .xlsm workbook at [filePath] into a sibling
  /// `.qsheet` and returns the new file's path. The workbook is left in place.
  ///
  /// Throws an [ApiException] with status 409 when a `.qsheet` of that name
  /// already exists and [overwrite] was not set, so the caller can offer to
  /// replace it rather than silently overwriting the user's own work.
  static Future<String> convertXlsxToQsheet(
    String filePath, {
    String? serial,
    bool overwrite = false,
  }) async {
    final querySegments = <String>[
      'filePath=${Uri.encodeQueryComponent(filePath)}',
    ];
    final serialValue = serial?.trim() ?? '';
    if (serialValue.isNotEmpty) {
      querySegments.add('serial=${Uri.encodeQueryComponent(serialValue)}');
    }
    if (overwrite) {
      querySegments.add('overwrite=true');
    }
    final endpointUri = apiBaseUri.resolve('/api/v0/files/convert/xlsx');
    final uri = endpointUri.replace(query: querySegments.join('&'));
    final response = await instance.authenticatedPost(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // The conflict is answered by the caller, not by the message the Quark
      // sent with it, so the status is what travels.
      throw ApiException(response.statusCode, 'Failed to convert spreadsheet');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected convert response format');
    }
    final path = decoded['path'] as String? ?? '';
    if (path.isEmpty) {
      throw Exception('Convert response carried no path');
    }
    return path;
  }

  /// Returns filesystem metadata for [filePath]: whether it is a directory
  /// and its resolved [fileType] string (e.g. "image", "qdoc", "folder").
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
    final endpointUri = apiBaseUri.resolve('/api/v0/files/stat');
    final uri = endpointUri.replace(query: querySegments.join('&'));
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FilesRequestException(
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

    final endpointUri = apiBaseUri.resolve('/api/v0/files');
    final uri = endpointUri.replace(queryParameters: queryParams);

    final response = await instance.authenticatedDelete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to delete file');
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
    final uri = apiBaseUri
        .resolve('/api/v0/files')
        .replace(query: querySegments.join('&'));
    final response = await instance.authenticatedDelete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to delete files');
    }
  }

  static Future<void> moveFile(
    String oldPath,
    String newPath, {
    String? oldDeviceSerial,
    String? newDeviceSerial,
  }) async {
    final endpointUri = apiBaseUri.resolve('/api/v0/files');
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
      throw ApiException(response.statusCode, 'Failed to move file');
    }
  }

  static Future<void> createFolder(String folderPath, String folderName) async {
    final trimmedFolderPath = folderPath.trim();
    final endpointPath = trimmedFolderPath.isEmpty
        ? '/api/v0/files/folder/'
        : _joinPaths('/api/v0/files/folder', trimmedFolderPath);
    final endpointUri = apiBaseUri.resolve(endpointPath);

    final request = http.MultipartRequest('POST', endpointUri);
    request.fields['folderName'] = folderName;
    request.headers.addAll(_authHeaders);

    final response = await request.send();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to create folder');
    }
  }

  static Future<http.StreamedResponse> uploadFilesFromFormData(
    String uploadPath,
    List<http.MultipartFile> formDataFiles, {
    String? serial,
    bool overwrite = false,
  }) async {
    final uploadEndpointPath = _joinPaths('/api/v0/files/upload', uploadPath);
    final endpointUri = apiBaseUri.resolve(uploadEndpointPath);

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
      throw ApiException(response.statusCode, 'Failed to upload files');
    }

    return response;
  }

  static Future<String?> saveFile(
    String filePath, {
    String? serial,
    String? fileName,
  }) async {
    final uri = _buildDownloadUri(filePath, serial: serial);

    if (kIsWeb) {
      // A browser download has no temp file to stream onto, so this path still
      // holds the response in memory — the platform gives it nowhere else to go.
      final response = await instance.authenticatedGet(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(response.statusCode, 'Failed to download file');
      }
      return web_download.saveBytesForDownload(
        response.bodyBytes,
        _resolveDownloadFileName(
          response.headers['content-disposition'],
          preferredName: fileName,
          fallbackPath: filePath,
        ),
      );
    }

    // Everywhere else the download streams to a temp file and the save dialog
    // copies from there. It used to arrive as bodyBytes and then be copied
    // again by Uint8List.fromList, costing twice the file's size in RAM
    // before the dialog even opened (#1723).
    final downloaded = await instance.authenticatedDownload(uri);
    try {
      // Awaited, not just returned: the finally below deletes the temp file, and
      // an unawaited future would let that race the dialog reading it.
      return await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: downloaded.path,
          fileName: _resolveDownloadFileName(
            downloaded.headers['content-disposition'],
            preferredName: fileName,
            fallbackPath: filePath,
          ),
        ),
      );
    } finally {
      await downloaded.delete();
    }
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
    final endpointUri = apiBaseUri.resolve(
      '/api/v0/files/download-archive-file',
    );
    final uri = endpointUri.replace(query: querySegments.join('&'));
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        'Failed to download archive file',
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
    if (serverConvertedImageExtensions.contains(fileExtension(filePath))) {
      // Not just a web concern: Flutter's built-in image decoder (Skia, via
      // Image.memory) can't decode HEIC/TIFF/BMP/RAW on any platform without
      // a dedicated codec plugin, which this app doesn't bundle. Request the
      // server-side JPEG conversion everywhere, not only on web (#1567).
      final params = Map<String, String>.from(uri.queryParameters);
      params['format'] = 'jpeg';
      uri = uri.replace(queryParameters: params);
    }
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to download file');
    }

    return response.bodyBytes;
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
      throw ApiException(response.statusCode, 'Failed to download thumbnail');
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
    final uri = apiBaseUri
        .resolve('/api/v0/photos/metadata')
        .replace(queryParameters: params);
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to load photo metadata');
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
    final uri = apiBaseUri.resolve('/api/v0/photos/rotate');
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
      throw ApiException(response.statusCode, 'Failed to save rotation');
    }
  }

  /// Duplicates a photo on the server. Returns the relative path of the new
  /// file (e.g. "photos/IMG_001_copy.jpg").
  static Future<String> copyPhoto(String relPath, {String? serial}) async {
    final uri = apiBaseUri.resolve('/api/v0/photos/copy');
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
      throw ApiException(response.statusCode, 'Failed to copy photo');
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

    final endpointUri = apiBaseUri.resolve('/api/v0/files/download');
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
    final endpointUri = apiBaseUri.resolve('/api/v0/version');
    final response = await instance.authenticatedGet(endpointUri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        'Failed to get installed version',
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
    final endpointUri = apiBaseUri.resolve('/api/v0/version/available');
    final uri = all ? endpointUri.replace(query: 'all=true') : endpointUri;
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        'Failed to list available versions',
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
    final uri = apiBaseUri.resolve('/api/v0/videos/extract-frame');
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
      throw ApiException(response.statusCode, 'Failed to extract frame');
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
    final uri = apiBaseUri.resolve('/api/v0/videos/trim');
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
      throw ApiException(response.statusCode, 'Failed to trim video');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['relPath'] as String;
  }

  static Future<void> updateToVersion(String version) async {
    final endpointUri = apiBaseUri.resolve('/api/v0/version/update');
    final body = jsonEncode({'version': version});
    final response = await instance.authenticatedPost(
      endpointUri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to perform update');
    }
  }
}

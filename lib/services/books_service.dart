import 'dart:convert';

import 'package:quark/models/file_node.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The books API: `GET /api/v0/books`, every PDF and EPUB under the files
/// directory that the signed-in user can read (#1678).
///
/// The Quark walks its internal drive only, so every book comes back on the
/// empty device serial.
class BooksService with AuthenticatedService {
  BooksService._();
  static final BooksService instance = BooksService._();

  /// Lists the books, in the order the Quark walked them.
  static Future<List<FileNode>> list() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.replace(path: '/api/v0/books'),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'list books');
    }
    final decoded = jsonDecode(response.body);
    return [
      for (final json
          in (decoded is List ? decoded : const <Object?>[])
              .whereType<Map<String, dynamic>>())
        FileNode(
          name: json['fileName']?.toString() ?? '',
          size: (json['size'] as num?)?.toInt() ?? 0,
          isDir: false,
          deviceName: '',
          devicePath: '',
          deviceSerial: '',
          dirPath: json['relPath']?.toString() ?? '',
          fileType: json['type']?.toString() ?? '',
          modifiedAt: switch (json['mtime']) {
            final num seconds => DateTime.fromMillisecondsSinceEpoch(
              seconds.toInt() * 1000,
            ),
            _ => null,
          },
        ),
    ];
  }
}

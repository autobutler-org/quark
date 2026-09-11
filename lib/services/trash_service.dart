import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quark/models/trash_item.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The trash API: `/api/v0/trash`. Every call addresses one device's trash;
/// the empty serial is the internal disk.
///
/// A refusal throws [ApiException] rather than going through [throwApiError]:
/// the trash handlers answer with the Go error's text, which is not copy for a
/// user, so the status code is what [Errors] reads.
class TrashService with AuthenticatedService {
  TrashService._();
  static final TrashService instance = TrashService._();

  /// Lists [serial]'s trash, stamping each item with the device it came from.
  static Future<TrashListing> listTrash(
    String serial, {
    String deviceName = '',
  }) async {
    final uri = apiBaseUri.replace(
      path: '/api/v0/trash',
      queryParameters: {'serial': serial},
    );
    final response = await instance.authenticatedGet(uri);
    _check(response, 'list the trash');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = body['items'] as List? ?? const [];
    return TrashListing(
      retentionDays: (body['retentionDays'] as num?)?.toInt() ?? 0,
      items: items
          .whereType<Map<String, dynamic>>()
          .map(
            (json) => TrashItem.fromJson(
              json,
              deviceSerial: serial,
              deviceName: deviceName,
            ),
          )
          .toList(growable: false),
    );
  }

  /// Lists a folder in [serial]'s trash: the trashed item [trashName] when
  /// [path] is empty, or the folder at [path] inside it.
  static Future<TrashContents> listContents(
    String serial,
    String trashName,
    String path,
  ) async {
    final uri = apiBaseUri.replace(
      path: '/api/v0/trash/contents',
      queryParameters: {'serial': serial, 'trashName': trashName, 'path': path},
    );
    final response = await instance.authenticatedGet(uri);
    _check(response, 'list a trashed folder');
    return TrashContents.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Puts [items] back where they were deleted from and returns the restored
  /// paths. An item with a path restores just that from inside a trashed
  /// folder. All or nothing: a 409 means one of them has something in its
  /// way, and none were restored.
  static Future<List<String>> restore(
    String serial,
    List<TrashRef> items,
  ) async {
    final body = await _post('/api/v0/trash/restore', {
      'serial': serial,
      'items': items,
    }, 'restore from the trash');
    return (body['restoredPaths'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
  }

  /// Deletes [items] for good and returns how many went.
  static Future<int> deletePermanently(
    String serial,
    List<TrashRef> items,
  ) async {
    final body = await _post('/api/v0/trash/delete', {
      'serial': serial,
      'items': items,
    }, 'delete from the trash');
    return (body['deleted'] as num?)?.toInt() ?? 0;
  }

  /// Deletes everything in [serial]'s trash and returns how many went.
  static Future<int> empty(String serial) async {
    final body = await _post('/api/v0/trash/empty', {
      'serial': serial,
    }, 'empty the trash');
    return (body['deleted'] as num?)?.toInt() ?? 0;
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object> payload,
    String context,
  ) async {
    final response = await instance.authenticatedPost(
      apiBaseUri.resolve(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    _check(response, context);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static void _check(http.Response response, String context) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to $context');
    }
  }
}

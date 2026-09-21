import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Reads a file dropped onto a page whole, or returns null when the drop
/// carried nothing readable.
///
/// Shared by every page that takes a drop (#2214), so the browser fallback
/// below is written once.
Future<Uint8List?> readDroppedFileBytes(DropItemFile droppedItem) async {
  try {
    return await droppedItem.readAsBytes();
  } catch (_) {
    // Some browser drag sources (e.g. dragging from another browser tab or
    // certain file managers) expose an HTTP/HTTPS URL via droppedItem.path
    // rather than providing raw bytes directly. Blob URLs (blob:...) are
    // not fetchable this way — this fallback only applies to http/https paths.
    if (!kIsWeb) {
      rethrow;
    }

    final path = droppedItem.path;
    if (path.isEmpty) {
      return null;
    }

    final fallbackResponse = await http.get(Uri.parse(path));
    if (fallbackResponse.statusCode >= 200 &&
        fallbackResponse.statusCode < 300) {
      return fallbackResponse.bodyBytes;
    }

    throw Exception(
      'Dropped file read failed (${fallbackResponse.statusCode})',
    );
  }
}

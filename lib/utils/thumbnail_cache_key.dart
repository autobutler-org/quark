import 'dart:convert';

/// The disk cache key for the Quark thumbnail served at [url] (#1777).
///
/// Built from what identifies the picture and nothing else: the Quark ([host],
/// its saved address rather than the one in [url], which changes when the app
/// switches to remote access), the signed-in [account], and the path, `serial`
/// and `size` in [url]. The session token in [url] is left out, so signing in
/// again finds the thumbnails already on disk.
String thumbnailCacheKey(Uri url, {String? host, String? account}) =>
    // Encoded as a list so no part can run into the one beside it.
    jsonEncode([
      host ?? '',
      account ?? '',
      url.path,
      url.queryParameters['serial'] ?? '',
      url.queryParameters['size'] ?? '',
    ]);

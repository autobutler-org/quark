// Stub for non-io platforms (web). There is no dart:io HttpServer in a
// browser, and the browser owns TLS trust anyway, so there is nothing to
// proxy. Callers gate on [mediaNeedsLocalProxy], which is always false on web,
// and this never runs.
import 'package:quark/services/local_media_proxy.dart';

/// The web build's stand-in for the local media proxy, which needs `dart:io`. On web the browser handles TLS
/// trust and plays media straight from its URL, so this always throws.
Future<LocalMediaProxy> startLocalMediaProxy(
  Uri upstream, {
  Map<String, String>? headers,
}) {
  throw UnsupportedError(
    'LocalMediaProxy requires dart:io; on web the browser handles TLS trust '
    'and media is played directly from its URL.',
  );
}

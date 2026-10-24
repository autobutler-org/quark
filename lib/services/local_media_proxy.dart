/// Loopback proxy that lets the native media players reach a quark serving a
/// self-signed certificate.
///
/// `video_player` hands playback to AVPlayer on iOS and ExoPlayer on Android.
/// Both do their own TLS validation inside the platform networking stack, so
/// neither sees [buildLocalTrustHttpClient] or the [LocalTrustHttpOverrides]
/// installed at startup — the app's self-signed exception simply does not
/// apply to them, and the handshake failure comes back as an opaque
/// `PlatformException(VideoError, ...)`.
///
/// [LocalMediaProxy] terminates TLS in Dart, where the exception does work,
/// and re-serves the bytes to the native player over plaintext HTTP bound to
/// `127.0.0.1`. The socket is loopback-only, so the plaintext hop never leaves
/// the device.
///
/// Range requests are forwarded and range responses echoed back verbatim, so
/// seeking and progressive download keep working; the body is piped rather
/// than buffered, so memory stays flat regardless of file size.
library;

import 'package:flutter/foundation.dart';
import 'package:quark/services/local_media_proxy_stub.dart'
    if (dart.library.io) 'package:quark/services/local_media_proxy_io.dart'
    as impl;
import 'package:quark/services/local_trust.dart';
import 'package:quark/utils/error_text.dart';

/// Thrown when the upstream quark answers a media request with a non-2xx
/// status.
///
/// Playback pages catch this to report "not found" or "session expired"
/// instead of routing every failure through the "unsupported codec/profile"
/// message that issue #1627 is about.
class MediaUpstreamException implements Exception {
  const MediaUpstreamException(this.statusCode, this.reasonPhrase);

  final int statusCode;
  final String reasonPhrase;

  /// A message safe to show the user, phrased in terms of the server's answer
  /// rather than the file's contents.
  String get userMessage =>
      Errors.message(ApiException(statusCode, reasonPhrase), 'play this file');

  @override
  String toString() => 'MediaUpstreamException($statusCode $reasonPhrase)';
}

/// A running loopback proxy in front of exactly one upstream media URL.
///
/// Create with [LocalMediaProxy.start], hand [localUrl] to the player, and
/// call [close] from the owning page's `dispose`.
abstract class LocalMediaProxy {
  /// The `http://127.0.0.1:<port>/<token>` URL to give the player.
  Uri get localUrl;

  /// The first non-2xx status seen from upstream, if any.
  ///
  /// The native player reports a load failure without telling us why, so the
  /// page reads this afterwards to distinguish "server said 404" from "the
  /// codec really is unsupported".
  MediaUpstreamException? get lastUpstreamError;

  /// Shuts the listening socket down, dropping in-flight connections.
  Future<void> close();

  /// Binds a proxy on loopback pointed at [upstream].
  ///
  /// [headers] are merged into every forwarded request. Leave it null and the
  /// proxy sends the same `Authorization: Bearer` header the rest of the app
  /// sends (`AuthenticatedService.authHeaders`), so authenticated media URLs
  /// keep working; pass an explicit map in tests.
  static Future<LocalMediaProxy> start(
    Uri upstream, {
    Map<String, String>? headers,
  }) => impl.startLocalMediaProxy(upstream, headers: headers);
}

/// Whether media pointed at [url] needs to be routed through a loopback proxy.
///
/// True only for HTTPS URLs whose host is local per [isLocalTrustHost] — the
/// single source of truth for "this host is expected to present a self-signed
/// certificate". A properly verified remote host (Tailscale, a real domain)
/// streams directly, exactly as before.
///
/// Always false on web: there is no `dart:io` `HttpServer` in a browser, and
/// the browser owns TLS trust anyway.
bool mediaNeedsLocalProxy(Uri url) {
  if (kIsWeb) return false;
  if (url.scheme != 'https') return false;
  return isLocalTrustHost(url.host);
}

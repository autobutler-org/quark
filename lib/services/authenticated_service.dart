import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/local_trust.dart';
import 'package:quark/utils/error_text.dart';

/// Thrown when an API call returns 401 — session expired or invalid.
class UnauthorizedException implements Exception {
  const UnauthorizedException();
  @override
  String toString() => 'Session expired. Please log in again.';
}

/// How long to wait for a TCP connection before giving up on the Quark.
///
/// Bounds only the connect phase, so it is safe on requests with a large body
/// (chunked uploads) — those are bounded separately by the upload manager's
/// own per-attempt timeout.
/// A host that is silent rather than actively refusing otherwise hangs for
/// however long the OS feels like waiting.
const Duration kConnectTimeout = Duration(seconds: 5);

/// Returns an [http.Client] that trusts self-signed certificates when the
/// active host is a local/LAN address (see [isLocalTrustHost]).
///
/// On web, the browser manages TLS trust natively and imposes its own connect
/// deadline, so the default client is returned unchanged.
http.Client buildLocalTrustHttpClient() {
  if (kIsWeb) return http.Client();

  final host = _extractHost(AppSettings.instance.activeHost);

  final inner = HttpClient()..connectionTimeout = kConnectTimeout;
  if (isLocalTrustHost(host)) {
    inner.badCertificateCallback = (cert, host, port) => true;
  }
  return IOClient(inner);
}

/// Extracts the hostname portion from a URL string (or returns the raw string
/// when it cannot be parsed as a URI).
String _extractHost(String? url) {
  if (url == null || url.isEmpty) return '';
  try {
    return Uri.parse(url).host;
  } catch (_) {
    return url;
  }
}

http.Client? _sharedClient;

/// Host key [_sharedClient] was built for. Null means nothing is cached; `''`
/// is a real key, since [_extractHost] returns it for an unset active host.
String? _sharedClientHost;

/// Builds the client [sharedHttpClient] hands out. Overridable in tests.
@visibleForTesting
http.Client Function() sharedHttpClientFactory = buildLocalTrustHttpClient;

/// The one [http.Client] every API call to the active host goes out through.
///
/// A client that is closed after each request also closes its socket, so every
/// call paid a fresh TCP connect plus TLS handshake — tens of milliseconds on a
/// LAN, the dominant cost of a listing over remote access, and a radio wake-up
/// on a phone. Keeping one client alive lets the next request ride the
/// connection the last one opened, which is also what makes a cheap answer
/// cheap: a 304 revalidation only saves anything when it does not have to
/// build a connection to ask.
///
/// The client is rebuilt when [AppSettings.activeHost] changes, because trust
/// (see [isLocalTrustHost]) is decided per host and pooled connections to the
/// old one are worthless.
http.Client get sharedHttpClient {
  final host = _extractHost(AppSettings.instance.activeHost);
  final cached = _sharedClient;
  if (cached != null && _sharedClientHost == host) return cached;

  cached?.close();
  _sharedClientHost = host;
  return _sharedClient = sharedHttpClientFactory();
}

/// Closes and forgets the shared client, so the next access builds a new one.
@visibleForTesting
void resetSharedHttpClient() {
  _sharedClient?.close();
  _sharedClient = null;
  _sharedClientHost = null;
}

/// Mixin providing a shared auth header helper for services that talk to the quark API.
///
/// Include this mixin in any service class that makes HTTP calls to the quark.
/// Use [authHeaders] to inject the session token into every request.
/// Call [checkUnauthorized] after every response to handle session expiry.
mixin AuthenticatedService {
  /// Returns an Authorization header map when a session token is set, empty otherwise.
  /// Spread into your http call headers: `headers: authHeaders`.
  Map<String, String> get authHeaders {
    final token = AppSettings.instance.sessionToken;
    if (token == null) return {};
    return {'Authorization': 'Bearer $token'};
  }

  /// Checks if [response] is a 401 and, if so, clears the session token and
  /// throws [UnauthorizedException]. The router's redirect guard will pick up
  /// the cleared token on the next navigation and send the user to the login page.
  ///
  /// Call this after every authenticated API response:
  /// ```dart
  /// final response = await http.get(uri, headers: _authHeaders);
  /// checkUnauthorized(response);
  /// if (response.statusCode != 200) throw Exception('...');
  /// ```
  void checkUnauthorized(http.Response response) {
    if (response.statusCode == 401) {
      AppSettings.instance.setSessionToken(null);
      throw const UnauthorizedException();
    }
  }

  /// The shared HTTP client for the active host — see [sharedHttpClient].
  ///
  /// Do not close it. It is reused by every other call on every other service,
  /// and closing it drops the pooled connections that make it worth having.
  http.Client get httpClient => sharedHttpClient;

  /// Authenticated GET — injects auth headers and checks for 401 automatically.
  Future<http.Response> authenticatedGet(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final response = await httpClient.get(
      uri,
      headers: {...authHeaders, ...?headers},
    );
    checkUnauthorized(response);
    return response;
  }

  /// Authenticated GET streamed straight onto disk, returning where it landed.
  ///
  /// The body never enters memory. A download used to arrive whole as
  /// `response.bodyBytes` and get copied a second time on its way to the file,
  /// so saving a large file cost twice its size in RAM on a phone (#1723).
  ///
  /// The caller owns the returned file and must [DownloadedFile.delete] it.
  /// Not available on web, which has no filesystem to stream onto.
  Future<DownloadedFile> authenticatedDownload(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final request = http.Request('GET', uri)
      ..headers.addAll({...authHeaders, ...?headers});
    final response = await httpClient.send(request);

    // An unread body pins the connection out of the pool for good, so the
    // error paths have to discard it before they leave. `drain` throws it
    // away as it arrives rather than accumulating it.
    if (response.statusCode == 401) {
      await response.stream.drain<void>();
      AppSettings.instance.setSessionToken(null);
      throw const UnauthorizedException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw ApiException(response.statusCode, 'Failed to download file');
    }

    final dir = await Directory.systemTemp.createTemp('quark_download_');
    final file = File('${dir.path}/download');
    final sink = file.openWrite();
    try {
      await response.stream.pipe(sink);
    } finally {
      await sink.close();
    }
    return DownloadedFile._(dir, file.path, response.headers);
  }

  /// Authenticated POST — injects auth headers and checks for 401 automatically.
  Future<http.Response> authenticatedPost(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final response = await httpClient.post(
      uri,
      headers: {...authHeaders, ...?headers},
      body: body,
    );
    checkUnauthorized(response);
    return response;
  }

  /// Authenticated PATCH — injects auth headers and checks for 401 automatically.
  Future<http.Response> authenticatedPatch(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final response = await httpClient.patch(
      uri,
      headers: {...authHeaders, ...?headers},
      body: body,
    );
    checkUnauthorized(response);
    return response;
  }

  /// Authenticated DELETE — injects auth headers and checks for 401 automatically.
  Future<http.Response> authenticatedDelete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final response = await httpClient.delete(
      uri,
      headers: {...authHeaders, ...?headers},
      body: body,
    );
    checkUnauthorized(response);
    return response;
  }

  /// Authenticated PUT — injects auth headers and checks for 401 automatically.
  Future<http.Response> authenticatedPut(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final response = await httpClient.put(
      uri,
      headers: {...authHeaders, ...?headers},
      body: body,
    );
    checkUnauthorized(response);
    return response;
  }
}

/// A download that landed on disk instead of in memory, plus the response
/// headers the caller still needs (Content-Disposition, for the file name).
class DownloadedFile {
  const DownloadedFile._(this._dir, this.path, this.headers);

  final Directory _dir;

  /// Path of the downloaded file. Valid until [delete].
  final String path;

  /// Response headers from the download.
  final Map<String, String> headers;

  /// Removes the temporary file and the directory holding it. Failure to clean
  /// up is not worth failing a completed download over, so it is swallowed.
  Future<void> delete() async {
    try {
      await _dir.delete(recursive: true);
    } catch (_) {
      // Best effort: the OS reclaims its own temp directory.
    }
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/listing_cache_config.dart';

/// A single full-text search result from the backend FTS5 index.
class ContentSearchResult {
  const ContentSearchResult({
    required this.deviceSerial,
    required this.relPath,
    required this.snippet,
  });

  /// Empty string means the internal (non-USB) device.
  final String deviceSerial;

  /// Path relative to the device's files root (e.g. "docs/meeting.qdoc").
  final String relPath;

  /// HTML fragment with matched terms wrapped in `<b>…</b>`.
  final String snippet;

  /// The filename portion of [relPath].
  String get filename {
    final idx = relPath.lastIndexOf('/');
    return idx < 0 ? relPath : relPath.substring(idx + 1);
  }

  /// Strips HTML tags from [snippet] to produce plain text.
  String get plainSnippet => snippet.replaceAll(RegExp(r'<[^>]*>'), '');

  factory ContentSearchResult.fromJson(Map<String, dynamic> json) {
    return ContentSearchResult(
      deviceSerial: (json['serial'] as String?) ?? '',
      relPath: (json['relPath'] as String?) ?? '',
      snippet: (json['snippet'] as String?) ?? '',
    );
  }
}

/// Calls `GET /api/v0/files/search/content?q=<query>` and returns up to 50
/// results (the backend's default limit).
///
/// Remembers the last [ListingCacheConfig.maxSearches] answers for the active
/// Quark and account, and two identical searches in flight share one request
/// (#1780). Any file event that can change a listing forgets them all, since a
/// document's contents may have changed with it.
class ContentSearchService with AuthenticatedService {
  ContentSearchService._();
  static final ContentSearchService instance = ContentSearchService._();

  /// A map literal keeps insertion order, so the first key is the least
  /// recently used.
  static final _memo = <String, List<ContentSearchResult>>{};
  static final _inFlight = <String, Future<List<ContentSearchResult>>>{};

  /// Bumped by [forget], so a request that started before it is not
  /// remembered after it.
  static int _generation = 0;
  static StreamSubscription<FileEvent>? _events;

  /// The file events that clear the memo. Overridable in tests.
  @visibleForTesting
  static Stream<FileEvent> Function() fileEvents = () =>
      EventsService.instance.events;

  /// Forgets every remembered search and stops sharing the ones in flight.
  static void forget() {
    _generation++;
    _memo.clear();
    _inFlight.clear();
  }

  /// [forget]s and drops the event subscription, for a test's tear-down.
  @visibleForTesting
  static void reset() {
    forget();
    _events?.cancel();
    _events = null;
  }

  /// Returns content-search results for [query].
  ///
  /// Never throws: on a transport error, a non-2xx status, or a body that is
  /// not a JSON array, it logs and returns an empty list so the caller can
  /// clear its loading state. A failed search is not remembered.
  static Future<List<ContentSearchResult>> search(String query) {
    final q = query.trim();
    if (q.isEmpty) return Future.value(const []);
    _events ??= fileEvents().listen((e) {
      if (e.changesListing) forget();
    });
    final key =
        '$apiBaseUrl\u0000${AppSettings.instance.username ?? ''}\u0000$q';
    final hit = _memo.remove(key);
    if (hit != null) {
      _memo[key] = hit;
      return Future.value(hit);
    }
    final generation = _generation;
    return _inFlight[key] ??= _fetch(q).then((results) {
      if (generation != _generation) return results ?? const [];
      _inFlight.remove(key);
      if (results == null) return const <ContentSearchResult>[];
      _memo[key] = results;
      while (_memo.length > ListingCacheConfig.maxSearches) {
        _memo.remove(_memo.keys.first);
      }
      return results;
    });
  }

  /// One request for [query], or null when it failed. Note that an unmatched
  /// API path does not 404 — the server's SPA fallback answers 200 with
  /// `index.html`, so the body must be validated, not just the status code.
  static Future<List<ContentSearchResult>?> _fetch(String query) async {
    final uri = apiBaseUri.replace(
      path: '/api/v0/files/search/content',
      queryParameters: {'q': query},
    );
    try {
      final response = await instance.authenticatedGet(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('content search: $uri returned ${response.statusCode}');
        return null;
      }
      // WrapApiRoute writes the handler's payload directly (c.JSON(status,
      // resp.Data)), so a list endpoint answers with a bare JSON array — there
      // is no {"data": …} envelope to unwrap.
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        debugPrint('content search: $uri returned ${decoded.runtimeType}');
        return null;
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ContentSearchResult.fromJson)
          .toList(growable: false);
    } on FormatException catch (e) {
      // Reached when the SPA fallback serves HTML for an unmatched path.
      debugPrint('content search: $uri returned a non-JSON body ($e)');
      return null;
    } catch (e) {
      debugPrint('content search: $uri failed ($e)');
      return null;
    }
  }
}

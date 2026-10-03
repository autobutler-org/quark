import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/listing_cache_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ContentSearchResult.fromJson', () {
    // The exact body returned by GET /api/v0/files/search/content. The
    // handler's payload is written directly by WrapApiRoute, so this is a bare
    // array with a `serial` key — not a {"data": …} envelope, and not
    // `deviceSerial`.
    const realResponse =
        '[{"serial":"","relPath":"something.txt.qdoc",'
        '"snippet":"\\u003cb\\u003e hello world\\u003c/b\\u003e"}]';

    test('parses the backend response shape', () {
      final decoded = jsonDecode(realResponse) as List;
      final results = decoded
          .whereType<Map<String, dynamic>>()
          .map(ContentSearchResult.fromJson)
          .toList();

      expect(results, hasLength(1));
      expect(results.single.relPath, 'something.txt.qdoc');
      expect(results.single.deviceSerial, '');
      expect(results.single.snippet, '<b> hello world</b>');
    });

    test('exposes filename and tag-stripped snippet for the result tile', () {
      final decoded = jsonDecode(realResponse) as List;
      final result = ContentSearchResult.fromJson(
        decoded.first as Map<String, dynamic>,
      );

      expect(result.filename, 'something.txt.qdoc');
      expect(result.plainSnippet, ' hello world');
    });

    test('reads nested paths down to the filename', () {
      final result = ContentSearchResult.fromJson({
        'serial': 'ABC123',
        'relPath': 'notes/2026/meeting.qdoc',
        'snippet': 'x',
      });

      expect(result.filename, 'meeting.qdoc');
      expect(result.deviceSerial, 'ABC123');
    });

    test('tolerates missing keys', () {
      final result = ContentSearchResult.fromJson({});

      expect(result.deviceSerial, '');
      expect(result.relPath, '');
      expect(result.snippet, '');
    });
  });

  group('ContentSearchService memo (#1780)', () {
    late List<String> requested;
    late StreamController<FileEvent> events;
    var status = 200;
    Completer<void>? gate;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      requested = [];
      status = 200;
      gate = null;
      events = StreamController<FileEvent>.broadcast();
      ContentSearchService.fileEvents = () => events.stream;
      resetSharedHttpClient();
      sharedHttpClientFactory = () => MockClient((request) async {
        final q = request.url.queryParameters['q']!;
        requested.add(q);
        await gate?.future;
        return http.Response(
          jsonEncode([
            {'serial': '', 'relPath': '$q.qdoc', 'snippet': q},
          ]),
          status,
        );
      });
    });

    tearDown(() {
      ContentSearchService.reset();
      events.close();
      resetSharedHttpClient();
      sharedHttpClientFactory = buildLocalTrustHttpClient;
    });

    test('a repeated search is answered without a second request', () async {
      final first = await ContentSearchService.search('budget');
      final again = await ContentSearchService.search(' budget ');

      expect(requested, ['budget']);
      expect(again.single.relPath, first.single.relPath);
    });

    test('a different search is a miss', () async {
      await ContentSearchService.search('budget');
      final other = await ContentSearchService.search('travel');

      expect(requested, ['budget', 'travel']);
      expect(other.single.relPath, 'travel.qdoc');
    });

    test('two identical searches in flight share one request', () async {
      gate = Completer<void>();
      final a = ContentSearchService.search('budget');
      final b = ContentSearchService.search('budget');
      gate!.complete();

      expect((await a).single.relPath, 'budget.qdoc');
      expect((await b).single.relPath, 'budget.qdoc');
      expect(requested, ['budget']);
    });

    test('a failed search is not remembered', () async {
      status = 500;
      expect(await ContentSearchService.search('budget'), isEmpty);
      status = 200;

      expect(await ContentSearchService.search('budget'), hasLength(1));
      expect(requested, ['budget', 'budget']);
    });

    test('a file event that changes listings clears the memo', () async {
      await ContentSearchService.search('budget');
      events.add(const FileEvent(kind: 'job_progress', path: ''));
      await pumpEventQueue();
      await ContentSearchService.search('budget');
      expect(requested, ['budget']);

      events.add(const FileEvent(kind: 'upload', path: 'budget.qdoc'));
      await pumpEventQueue();
      await ContentSearchService.search('budget');
      expect(requested, ['budget', 'budget']);
    });

    test('a search in flight when the memo clears is not remembered', () async {
      gate = Completer<void>();
      final stale = ContentSearchService.search('budget');
      await pumpEventQueue();
      ContentSearchService.forget();
      gate!.complete();
      await stale;
      gate = null;

      await ContentSearchService.search('budget');
      expect(requested, ['budget', 'budget']);
    });

    test('keeps only the most recent searches', () async {
      for (var i = 0; i <= ListingCacheConfig.maxSearches; i++) {
        await ContentSearchService.search('q$i');
      }
      requested.clear();

      await ContentSearchService.search('q${ListingCacheConfig.maxSearches}');
      await ContentSearchService.search('q0');
      expect(requested, ['q0']);
    });
  });
}

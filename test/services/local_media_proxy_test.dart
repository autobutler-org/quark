import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/local_media_proxy.dart';

final _rangePattern = RegExp(r'bytes=(\d*)-(\d*)');

/// A stand-in for the quark's download endpoint.
///
/// Serves [body] over plaintext with the same RFC 7233 semantics Go's
/// `http.ServeContent` gives the real endpoint, and records what it was asked
/// for so the tests can assert on the upstream side of the conversation.
class _FakeUpstream {
  _FakeUpstream._(this._server, this.contentType);

  final HttpServer _server;
  final String contentType;

  final List<String> requestedRanges = <String>[];
  final List<String> methods = <String>[];
  final List<Map<String, String>> receivedHeaders = <Map<String, String>>[];

  /// Total bytes actually written to the wire, across all requests.
  int bytesServed = 0;

  int get port => _server.port;
  Uri get url => Uri.parse('http://127.0.0.1:$port/media.mp4');

  static Future<_FakeUpstream> start({
    required List<int> body,
    String contentType = 'video/mp4',
    int status = HttpStatus.ok,
    String reason = '',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    final upstream = _FakeUpstream._(server, contentType);

    server.listen((request) async {
      upstream.methods.add(request.method);
      upstream.receivedHeaders.add({
        for (final name in const [
          'authorization',
          'range',
          'x-test',
          'accept-encoding',
        ])
          if (request.headers.value(name) != null)
            name: request.headers.value(name)!,
      });

      final response = request.response;

      if (status != HttpStatus.ok) {
        response.statusCode = status;
        if (reason.isNotEmpty) response.reasonPhrase = reason;
        await response.close();
        return;
      }

      final rangeHeader = request.headers.value('range');
      if (rangeHeader != null) {
        upstream.requestedRanges.add(rangeHeader);
        final match = _rangePattern.firstMatch(rangeHeader.trim());
        if (match != null) {
          final start = int.parse(match.group(1)!);
          final endGroup = match.group(2)!;
          final end = endGroup.isEmpty ? body.length - 1 : int.parse(endGroup);

          if (start >= body.length) {
            response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            response.headers.set('content-range', 'bytes */${body.length}');
            await response.close();
            return;
          }

          final slice = body.sublist(start, end + 1);
          response.statusCode = HttpStatus.partialContent;
          response.headers.set('content-type', contentType);
          response.headers.set('accept-ranges', 'bytes');
          response.headers.set(
            'content-range',
            'bytes $start-$end/${body.length}',
          );
          response.contentLength = slice.length;
          upstream.bytesServed += slice.length;
          response.add(slice);
          await response.close();
          return;
        }
      }

      response.statusCode = HttpStatus.ok;
      response.headers.set('content-type', contentType);
      response.headers.set('accept-ranges', 'bytes');
      response.contentLength = body.length;
      upstream.bytesServed += body.length;
      response.add(body);
      await response.close();
    });

    return upstream;
  }

  Future<void> close() => _server.close(force: true);
}

/// A fake that dribbles a large body out in chunks, so a test can watch bytes
/// arrive at the client before the upstream has finished writing.
class _SlowUpstream {
  _SlowUpstream._(this._server);

  final HttpServer _server;
  final Completer<void> _release = Completer<void>();

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/slow.mp4');

  static Future<_SlowUpstream> start({
    required int chunkSize,
    required int chunkCount,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    final upstream = _SlowUpstream._(server);

    server.listen((request) async {
      final response = request.response;
      response.statusCode = HttpStatus.ok;
      response.headers.set('content-type', 'video/mp4');
      response.contentLength = chunkSize * chunkCount;
      // First chunk goes out immediately; the rest waits until the test says
      // so. A proxy that buffered would not deliver anything until the end.
      response.add(List<int>.filled(chunkSize, 1));
      await response.flush();
      await upstream._release.future;
      for (var i = 1; i < chunkCount; i++) {
        response.add(List<int>.filled(chunkSize, 1));
      }
      await response.close();
    });

    return upstream;
  }

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  Future<void> close() {
    release();
    return _server.close(force: true);
  }
}

Future<List<int>> _readAll(HttpClientResponse response) =>
    response.expand((chunk) => chunk).toList();

Future<HttpClientResponse> _get(Uri url, {String? range}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    if (range != null) request.headers.set('range', range);
    return await request.close();
  } finally {
    client.close();
  }
}

void main() {
  group('mediaNeedsLocalProxy', () {
    test('engages for https on a local host', () {
      expect(
        mediaNeedsLocalProxy(
          Uri.parse('https://brandons-macbook-pro-2.local/api/v0/files'),
        ),
        isTrue,
      );
      expect(
        mediaNeedsLocalProxy(Uri.parse('https://192.168.1.42/api/v0/files')),
        isTrue,
      );
    });

    test('stays out of the way for verifiable remote hosts', () {
      expect(
        mediaNeedsLocalProxy(Uri.parse('https://quark.example.com/media.mp4')),
        isFalse,
      );
      expect(
        mediaNeedsLocalProxy(Uri.parse('https://100.64.0.1/media.mp4')),
        isFalse,
      );
    });

    test('ignores plaintext URLs, which have no cert to distrust', () {
      expect(
        mediaNeedsLocalProxy(Uri.parse('http://butler.local/media.mp4')),
        isFalse,
      );
    });
  });

  group('LocalMediaProxy', () {
    late _FakeUpstream upstream;
    late LocalMediaProxy proxy;

    final body = List<int>.generate(4096, (i) => i % 251);

    tearDown(() async {
      await proxy.close();
      await upstream.close();
    });

    Future<void> startProxy({
      List<int>? withBody,
      String contentType = 'video/mp4',
      int status = HttpStatus.ok,
      String reason = '',
      Map<String, String>? headers,
    }) async {
      upstream = await _FakeUpstream.start(
        body: withBody ?? body,
        contentType: contentType,
        status: status,
        reason: reason,
      );
      proxy = await LocalMediaProxy.start(
        upstream.url,
        headers: headers ?? const {},
      );
    }

    test('binds on loopback with an unguessable path', () async {
      await startProxy();

      expect(proxy.localUrl.scheme, 'http');
      expect(proxy.localUrl.host, '127.0.0.1');
      expect(proxy.localUrl.port, greaterThan(0));
      // 16 random bytes, hex-encoded.
      expect(proxy.localUrl.path, matches(r'^/[0-9a-f]{32}$'));
    });

    test('passes a plain GET through byte for byte', () async {
      await startProxy();

      final response = await _get(proxy.localUrl);
      final received = await _readAll(response);

      expect(response.statusCode, 200);
      expect(received, equals(body));
      expect(proxy.lastUpstreamError, isNull);
    });

    test('echoes content-type, accept-ranges and content-length', () async {
      await startProxy(contentType: 'audio/mpeg');

      final response = await _get(proxy.localUrl);
      addTearDown(() => response.drain<void>());

      expect(response.headers.value('content-type'), 'audio/mpeg');
      expect(response.headers.value('accept-ranges'), 'bytes');
      expect(response.headers.contentLength, body.length);
    });

    test('forwards Range and returns 206 with the right slice', () async {
      await startProxy();

      final response = await _get(proxy.localUrl, range: 'bytes=100-199');
      final received = await _readAll(response);

      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value('content-range'),
        'bytes 100-199/${body.length}',
      );
      expect(received.length, 100);
      expect(received, equals(body.sublist(100, 200)));
      expect(upstream.requestedRanges, ['bytes=100-199']);
      // The seek must not have dragged the whole file across the wire; that is
      // the difference between streaming and downloading.
      expect(upstream.bytesServed, 100);
    });

    test('passes 416 through without calling it a playback failure', () async {
      await startProxy();

      final response = await _get(proxy.localUrl, range: 'bytes=99999-');
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      // A seek past the end is a normal thing for a player to do.
      expect(proxy.lastUpstreamError, isNull);
    });

    test('rejects a path that is not the token', () async {
      await startProxy();

      final wrong = proxy.localUrl.replace(path: '/guessed');
      final response = await _get(wrong);
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.notFound);
      // Nothing reached the upstream, so this cannot be used as an open proxy.
      expect(upstream.methods, isEmpty);
    });

    test('rejects methods other than GET and HEAD', () async {
      await startProxy();

      final client = HttpClient();
      addTearDown(() => client.close());
      final request = await client.postUrl(proxy.localUrl);
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(upstream.methods, isEmpty);
    });

    test('serves HEAD without a body', () async {
      await startProxy();

      final client = HttpClient();
      addTearDown(() => client.close());
      final request = await client.headUrl(proxy.localUrl);
      final response = await request.close();
      final received = await _readAll(response);

      expect(response.statusCode, 200);
      expect(received, isEmpty);
      expect(upstream.methods, ['HEAD']);
    });

    test('forwards the caller-supplied auth headers', () async {
      await startProxy(
        headers: {'Authorization': 'Bearer tkn', 'X-Test': 'yes'},
      );

      final response = await _get(proxy.localUrl);
      await response.drain<void>();

      expect(upstream.receivedHeaders.single['authorization'], 'Bearer tkn');
      expect(upstream.receivedHeaders.single['x-test'], 'yes');
    });

    test('surfaces a 404 as a named error, not a codec problem', () async {
      await startProxy(status: HttpStatus.notFound, reason: 'Not Found');

      final response = await _get(proxy.localUrl);
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.notFound);

      final error = proxy.lastUpstreamError;
      expect(error, isA<MediaUpstreamException>());
      expect(error!.statusCode, 404);
      expect(error.userMessage, contains('no longer there'));
      expect(error.userMessage, isNot(contains('codec')));
    });

    test('surfaces a 401 as a session problem', () async {
      await startProxy(status: HttpStatus.unauthorized);

      final response = await _get(proxy.localUrl);
      await response.drain<void>();

      final error = proxy.lastUpstreamError;
      expect(error, isA<MediaUpstreamException>());
      expect(error!.statusCode, 401);
      expect(error.userMessage.toLowerCase(), contains('session'));
      expect(error.userMessage, isNot(contains('codec')));
    });

    test('stops listening after close', () async {
      await startProxy();
      final url = proxy.localUrl;
      await proxy.close();

      await expectLater(_get(url), throwsA(isA<SocketException>()));
    });

    test('survives one failed request and serves the next', () async {
      await startProxy();

      final bad = await _get(proxy.localUrl.replace(path: '/nope'));
      await bad.drain<void>();

      final good = await _get(proxy.localUrl);
      final received = await _readAll(good);

      expect(received, equals(body));
    });
  });

  group('LocalMediaProxy streaming', () {
    test('delivers bytes before the upstream has finished writing', () async {
      const chunkSize = 64 * 1024;
      const chunkCount = 16; // 1 MiB total.
      final slow = await _SlowUpstream.start(
        chunkSize: chunkSize,
        chunkCount: chunkCount,
      );
      final url = slow.url;
      final proxy = await LocalMediaProxy.start(url, headers: const {});
      addTearDown(() async {
        await proxy.close();
        await slow.close();
      });

      final client = HttpClient();
      addTearDown(() => client.close());
      final request = await client.getUrl(proxy.localUrl);
      final response = await request.close();

      final firstChunk = Completer<int>();
      var total = 0;
      final done = Completer<void>();
      response.listen(
        (data) {
          total += data.length;
          if (!firstChunk.isCompleted) firstChunk.complete(data.length);
        },
        onDone: () => done.complete(),
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
      );

      // Bytes must arrive while the upstream is still holding the rest back.
      // A proxy that collected the body into memory would time out here.
      final firstLength = await firstChunk.future.timeout(
        const Duration(seconds: 5),
      );
      expect(firstLength, greaterThan(0));
      expect(total, lessThan(chunkSize * chunkCount));

      slow.release();
      await done.future.timeout(const Duration(seconds: 10));
      expect(total, chunkSize * chunkCount);
    });
  });

  group('MediaUpstreamException', () {
    test('never blames the codec, and never shows the status code', () {
      for (final status in const [400, 401, 403, 404, 500, 502]) {
        final message = MediaUpstreamException(status, '').userMessage;
        expect(message, isNotEmpty);
        expect(message.toLowerCase(), isNot(contains('codec')));
        expect(message.toLowerCase(), isNot(contains('format')));
        // The status belongs in the log, not in front of the user (#1622).
        expect(message, isNot(contains('$status')));
      }
    });

    test('reads back as its status in toString', () {
      expect(
        const MediaUpstreamException(503, 'Service Unavailable').toString(),
        contains('503'),
      );
    });
  });
}

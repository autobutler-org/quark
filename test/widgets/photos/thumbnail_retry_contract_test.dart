import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/thumbnail_probe.dart';
import 'package:quark/services/thumbnail_backfill.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/thumbnail_cache_config.dart';
import 'package:quark/widgets/photos/photo_thumbnail.dart';
import 'package:quark/widgets/thumbnails/backfilling_thumbnail.dart';
import 'package:quark_widgets/quark_widgets.dart';

const _tileKey = ValueKey('thumbnail-contract-tile');

class _Reply {
  const _Reply(this.status, {this.body, this.retryAfter});

  final int status;
  final Uint8List? body;
  final Duration? retryAfter;
}

class _Request {
  const _Request(this.at, this.reply);

  final DateTime at;
  final _Reply reply;
}

/// A thumbnail endpoint with a response script, exposed through the same cache
/// manager seam the real photo tile uses.
class _ScriptedThumbnailEndpoint extends Fake implements BaseCacheManager {
  _ScriptedThumbnailEndpoint(this._script, this._now)
    : assert(_script.isNotEmpty);

  final List<_Reply> _script;
  final DateTime Function() _now;
  final _files = MemoryCacheSystem();
  final requests = <_Request>[];

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    final index = requests.length.clamp(0, _script.length - 1);
    final reply = _script[index];
    requests.add(_Request(_now(), reply));
    if (reply.status < 200 || reply.status >= 300) {
      throw HttpExceptionWithStatus(
        reply.status,
        'scripted thumbnail response',
        uri: Uri.parse(url),
      );
    }

    final file = await _files.createFile('thumbnail-${requests.length}.png');
    await file.writeAsBytes(reply.body!);
    yield FileInfo(
      file,
      FileSource.Online,
      _now().add(const Duration(days: 1)),
      url,
      statusCode: reply.status,
    );
  }

  @override
  Future<void> removeFile(String key) async {}
}

Future<Uint8List> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final image = await recorder.endRecording().toImage(8, 8);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

Future<void> _flushImageLoad(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

Widget _photoTile(Uri url, {String path = 'photos/contract.jpg'}) =>
    MaterialApp(
      home: Center(
        child: SizedBox.square(
          key: _tileKey,
          dimension: 100,
          child: PhotoThumbnail(url: url, path: path),
        ),
      ),
    );

Finder _insideTile(Finder matching) =>
    find.descendant(of: find.byKey(_tileKey), matching: matching);

void _expectNonBlackPlaceholder() {
  final placeholder = _insideTile(find.byType(ColoredBox));
  expect(
    placeholder,
    findsOneWidget,
    reason: 'the error placeholder is absent',
  );
  final color = (placeholder.evaluate().single.widget as ColoredBox).color;
  expect(color, isNot(Colors.black), reason: 'the tile settled to solid black');
  expect(_insideTile(find.byType(RawImage)), findsNothing);
}

/// A tile that has given up says why (#3509): the state [issue] keys, on a
/// backdrop that is not black, with no image.
void _expectSettled(ThumbnailIssue issue) {
  expect(
    _insideTile(find.byKey(ValueKey('photo_thumbnail_${issue.name}'))),
    findsOneWidget,
    reason: 'the tile is not in its ${issue.name} state',
  );
  expect(_insideTile(find.byType(QuarkThumbnailUnavailable)), findsOneWidget);
  final backdrop = _insideTile(find.byType(ColoredBox)).evaluate().single;
  expect((backdrop.widget as ColoredBox).color, isNot(Colors.black));
  expect(_insideTile(find.byType(RawImage)), findsNothing);
}

Future<Color> _centerColor(ui.Image image) async {
  final bytes = (await image.toByteData())!;
  final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  /// #3485: the server uses 503 + Retry-After while thumbnail work is busy.
  /// The tile must wait instead of spinning, then replace its placeholder with
  /// the image and stop requesting once it succeeds.
  testWidgets('503 Retry-After responses back off then resolve to the PNG', (
    tester,
  ) async {
    final png = (await tester.runAsync(() => _png(Colors.teal)))!;
    final retryAfter = ThumbnailCacheConfig.busyRetryDelay;
    final endpoint = _ScriptedThumbnailEndpoint([
      _Reply(503, retryAfter: retryAfter),
      _Reply(503, retryAfter: retryAfter),
      _Reply(200, body: png),
    ], tester.binding.clock.now);
    ThumbnailCacheManager.instance = endpoint;

    await tester.pumpWidget(
      _photoTile(Uri.parse('https://quark.test/thumbnails/eventual.png')),
    );
    await _flushImageLoad(tester);
    expect(endpoint.requests, hasLength(1));
    expect(endpoint.requests.single.reply.retryAfter, retryAfter);
    _expectNonBlackPlaceholder();

    await tester.pump(retryAfter);
    await _flushImageLoad(tester);
    expect(endpoint.requests, hasLength(2));
    expect(endpoint.requests.last.reply.retryAfter, retryAfter);
    _expectNonBlackPlaceholder();

    await tester.pump(retryAfter * 2);
    await _flushImageLoad(tester);
    expect(endpoint.requests, hasLength(3));
    final raw = tester.widget<RawImage>(_insideTile(find.byType(RawImage)));
    expect(raw.image, isNotNull);
    final shown = await tester.runAsync(() => _centerColor(raw.image!));
    expect(shown!.toARGB32(), Colors.teal.toARGB32());

    expect(
      endpoint.requests[1].at.difference(endpoint.requests[0].at),
      retryAfter,
    );
    expect(
      endpoint.requests[2].at.difference(endpoint.requests[1].at),
      retryAfter * 2,
    );
    await tester.pump(const Duration(minutes: 1));
    await _flushImageLoad(tester);
    expect(endpoint.requests, hasLength(3), reason: 'retried after success');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an always-busy endpoint is bounded and a later tile retries', (
    tester,
  ) async {
    final retryAfter = ThumbnailCacheConfig.busyRetryDelay;
    final endpoint = _ScriptedThumbnailEndpoint([
      _Reply(503, retryAfter: retryAfter),
    ], tester.binding.clock.now);
    ThumbnailCacheManager.instance = endpoint;
    final tile = _photoTile(
      Uri.parse('https://quark.test/thumbnails/always-busy.png'),
    );

    await tester.pumpWidget(tile);
    await _flushImageLoad(tester);
    var delay = retryAfter;
    for (var i = 0; i < ThumbnailCacheConfig.busyRetries; i++) {
      _expectNonBlackPlaceholder();
      await tester.pump(delay);
      await _flushImageLoad(tester);
      delay *= 2;
    }
    expect(endpoint.requests, hasLength(ThumbnailCacheConfig.busyRetries + 1));
    _expectSettled(ThumbnailIssue.loadFailed);

    await tester.pump(delay * 2);
    await _flushImageLoad(tester);
    expect(
      endpoint.requests,
      hasLength(ThumbnailCacheConfig.busyRetries + 1),
      reason: 'the retry budget was not bounded',
    );
    _expectSettled(ThumbnailIssue.loadFailed);

    // As when a grid tile scrolls beyond the cache extent, dispose it before
    // building the same photo again. A transient failure must not be cached.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(tile);
    await _flushImageLoad(tester);
    expect(
      endpoint.requests,
      hasLength(ThumbnailCacheConfig.busyRetries + 2),
      reason: 'the failed tile was permanently cached',
    );
    _expectNonBlackPlaceholder();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('404 and corrupt 200 bodies settle without retry storms', (
    tester,
  ) async {
    final cases = <(String, _Reply, ThumbnailIssue)>[
      ('gone', const _Reply(404), ThumbnailIssue.missing),
      (
        'corrupt',
        _Reply(200, body: Uint8List.fromList([0, 1, 2, 3])),
        ThumbnailIssue.unreadable,
      ),
    ];

    for (final (name, reply, issue) in cases) {
      final endpoint = _ScriptedThumbnailEndpoint([
        reply,
      ], tester.binding.clock.now);
      ThumbnailCacheManager.instance = endpoint;
      await tester.pumpWidget(
        _photoTile(Uri.parse('https://quark.test/thumbnails/$name.png')),
      );
      await _flushImageLoad(tester);

      expect(endpoint.requests, hasLength(1), reason: '$name initial request');
      _expectSettled(issue);
      await tester.pump(const Duration(minutes: 1));
      await _flushImageLoad(tester);
      expect(endpoint.requests, hasLength(1), reason: '$name retried forever');
      _expectSettled(issue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      imageCache
        ..clear()
        ..clearLiveImages();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed client-thumbnail PUT leaves a non-black placeholder', (
    tester,
  ) async {
    var puts = 0;
    final backfill = ThumbnailBackfill(
      probe: (path, {serial}) async =>
          const ThumbnailProbe(served: false, clientRender: true, modTime: '1'),
      downloadOriginal: (path, {serial}) async => Uint8List.fromList([1]),
      renderFromBytes: (name, bytes) async => Uint8List.fromList([2]),
      putThumbnail: ({required path, serial, required thumbnail}) async {
        puts++;
        throw Exception('scripted PUT failure');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.square(
          key: _tileKey,
          dimension: 100,
          child: BackfillingThumbnail(
            path: 'photos/client-rendered.heic',
            backfill: backfill,
            builder: (context, generation, onFailed) {
              onFailed(const HttpExceptionWithStatus(404, 'missing'));
              return ColoredBox(color: Colors.grey.shade300);
            },
          ),
        ),
      ),
    );
    await _flushImageLoad(tester);

    expect(puts, 1);
    _expectNonBlackPlaceholder();
    await tester.pump(const Duration(minutes: 1));
    expect(puts, 1, reason: 'the failed PUT spun forever');
    expect(tester.takeException(), isNull);
  });
}

import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// A thumbnail cache that serves from memory, for
/// `ThumbnailCacheManager.instance`.
///
/// [serve] gives each URL's image bytes, or throws to refuse it: throw an
/// `HttpExceptionWithStatus` to answer with the Quark's status, as a real
/// fetch reaches the tile.
class FakeThumbnailStore extends Fake implements BaseCacheManager {
  FakeThumbnailStore(this.serve);

  /// Serves [png] for every thumbnail.
  FakeThumbnailStore.of(Uint8List png) : this((_) => png);

  final Uint8List Function(String url) serve;

  /// Every URL fetched, in order, refused ones included.
  final fetched = <String>[];

  final _files = MemoryCacheSystem();

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    fetched.add(url);
    final bytes = serve(url);
    final file = await _files.createFile('${fetched.length}.png');
    await file.writeAsBytes(bytes);
    yield FileInfo(
      file,
      FileSource.Online,
      DateTime.now().add(const Duration(days: 1)),
      url,
    );
  }

  @override
  Future<void> removeFile(String key) async {}
}

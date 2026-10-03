import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_type_listing_cache.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/listing_cache_config.dart';

FileNode _node(String name) => FileNode(
  name: name,
  size: 1,
  isDir: false,
  deviceName: '',
  devicePath: '',
  deviceSerial: '',
  dirPath: name,
);

void main() {
  var scope = 'quark-a';
  late List<String> fetched;
  late Object? failWith;
  late FileTypeListingCache cache;

  setUp(() {
    scope = 'quark-a';
    fetched = [];
    failWith = null;
    cache = FileTypeListingCache(
      fetcher: (type) async {
        fetched.add(type);
        if (failWith != null) throw failWith!;
        return [_node('$scope.$type')];
      },
      scope: () => scope,
    );
  });

  test('has nothing to show before the first fetch', () {
    expect(cache.peek('qdoc'), isNull);
  });

  test('a fetch is shown by the next peek, per file type', () async {
    await cache.fetch('qdoc');

    expect(cache.peek('qdoc')!.single.name, 'quark-a.qdoc');
    expect(cache.peek('qsheet'), isNull);
  });

  test('a failed fetch keeps the previous listing', () async {
    await cache.fetch('qdoc');
    failWith = Exception('offline');

    await expectLater(cache.fetch('qdoc'), throwsException);
    expect(cache.peek('qdoc')!.single.name, 'quark-a.qdoc');
  });

  test('another Quark or account never sees this one\'s listing', () async {
    await cache.fetch('qdoc');
    scope = 'quark-b';

    expect(cache.peek('qdoc'), isNull);
  });

  test('keeps only the most recently used listings', () async {
    for (var i = 0; i <= ListingCacheConfig.maxListings; i++) {
      await cache.fetch('type$i');
      // Touching type0 keeps it; type1 becomes the oldest.
      cache.peek('type0');
    }

    expect(cache.peek('type0'), isNotNull);
    expect(cache.peek('type1'), isNull);
    expect(cache.peek('type${ListingCacheConfig.maxListings}'), isNotNull);
  });

  test('clear forgets everything', () async {
    await cache.fetch('qdoc');
    cache.clear();

    expect(cache.peek('qdoc'), isNull);
  });
}

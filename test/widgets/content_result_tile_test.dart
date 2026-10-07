import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/widgets/content_result_tile.dart';

/// A content hit opens the editor its own extension calls for (#2259), a
/// presentation included (#1161).
void main() {
  ContentSearchResult hit(String path) =>
      ContentSearchResult(deviceSerial: 'usb1', relPath: path, snippet: '');

  test('each kind opens in its own editor', () {
    expect(
      ContentResultTile.routeFor(hit('a/q1.qdoc')),
      '/docs/a/q1.qdoc?serial=usb1',
    );
    expect(
      ContentResultTile.routeFor(hit('a/b.qsheet')),
      '/sheets/a/b.qsheet?serial=usb1',
    );
    expect(
      ContentResultTile.routeFor(hit('a/deck.qslide')),
      '/slides/a/deck.qslide?serial=usb1',
    );
  });
}

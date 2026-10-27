import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/client_thumbnails.dart';

const _stl = '''solid tetra
facet normal 0 0 -1
 outer loop
  vertex 0 0 0
  vertex 1 0 0
  vertex 0 1 0
 endloop
endfacet
facet normal 0 -1 0
 outer loop
  vertex 0 0 0
  vertex 0 0 1
  vertex 1 0 0
 endloop
endfacet
facet normal -1 0 0
 outer loop
  vertex 0 0 0
  vertex 0 1 0
  vertex 0 0 1
 endloop
endfacet
facet normal 1 1 1
 outer loop
  vertex 1 0 0
  vertex 0 0 1
  vertex 0 1 0
 endloop
endfacet
endsolid tetra
''';

/// An STL picked for upload is drawn through the client thumbnail path
/// (#3227), the way a photo picked from disk is.
void main() {
  testWidgets('a model on disk uploads with a drawn thumbnail', (tester) async {
    final dir = Directory.systemTemp.createTempSync('model_thumbnail_source');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/tetra.stl')..writeAsStringSync(_stl);

    final jpeg = await tester.runAsync(
      () => renderThumbnailFromPath('tetra.stl', file.path),
    );
    expect(jpeg, isNotNull);
    expect(jpeg!.sublist(0, 2), [0xFF, 0xD8]);
  });

  testWidgets('a model that does not parse uploads without one', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('model_thumbnail_source');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/bad.stl')..writeAsStringSync('not a model');

    final jpeg = await tester.runAsync(
      () => renderThumbnailFromPath('bad.stl', file.path),
    );
    expect(jpeg, isNull);
  });
}

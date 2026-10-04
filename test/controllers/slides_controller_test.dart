import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/slides_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/content_search_service.dart';

FileNode _node(String path) => FileNode(
  name: path.split('/').last,
  size: 1,
  isDir: false,
  deviceName: '',
  devicePath: '',
  deviceSerial: '',
  dirPath: path,
);

/// The Slides page's state: the `.qslide` listing, its name and content
/// search, and creating a presentation (#1161).
void main() {
  test('starts from the cached listing and refreshes it', () async {
    var listing = [_node('old.qslide')];
    final c = SlidesController(
      peekSlides: () => [_node('cached.qslide')],
      listSlides: () async => listing,
    );
    addTearDown(c.dispose);
    expect(c.files.single.name, 'cached.qslide');
    await c.refresh();
    expect(c.files.single.name, 'old.qslide');
    listing = [_node('new.qslide'), _node('old.qslide')];
    await c.refresh();
    expect(c.files, hasLength(2));
  });

  test(
    'a failed refresh keeps the listing and the next one clears the error',
    () async {
      Object? failure = Exception('down');
      final c = SlidesController(
        peekSlides: () => [_node('a.qslide')],
        listSlides: () async {
          final f = failure;
          if (f != null) throw f;
          return [_node('b.qslide')];
        },
      );
      addTearDown(c.dispose);
      await c.refresh();
      expect(c.error, same(failure));
      expect(c.files.single.name, 'a.qslide');
      failure = null;
      await c.refresh();
      expect(c.error, isNull);
      expect(c.files.single.name, 'b.qslide');
    },
  );

  testWidgets('filters by name at once and adds slide content hits later', (
    tester,
  ) async {
    final queries = <String>[];
    final c = SlidesController(
      peekSlides: () => [_node('talks/pitch.qslide'), _node('q1.qslide')],
      listSlides: () async => const [],
      searchContent: (q) async {
        queries.add(q);
        return const [
          ContentSearchResult(
            deviceSerial: '',
            relPath: 'deep/roadmap.qslide',
            snippet: '<b>pitch</b>',
          ),
          ContentSearchResult(
            deviceSerial: '',
            relPath: 'notes.qdoc',
            snippet: '<b>pitch</b>',
          ),
        ];
      },
    );
    addTearDown(c.dispose);

    c.setQuery('pi');
    c.setQuery('pitch');
    expect(c.filtered.single.name, 'pitch.qslide');
    expect(c.contentSearching, isTrue);
    await tester.pump(const Duration(milliseconds: 400));
    expect(queries, ['pitch'], reason: 'typing is debounced');
    expect(c.contentSearching, isFalse);
    expect(c.contentResults.single.relPath, 'deep/roadmap.qslide');

    c.setQuery('');
    expect(c.filtered, hasLength(2));
    expect(c.contentResults, isEmpty);
    expect(c.contentSearching, isFalse);
  });

  test('create hands the name to the service and returns the path', () async {
    final c = SlidesController(
      peekSlides: () => null,
      listSlides: () async => const [],
      createPresentation: (name) async => 'home/ann/$name.qslide',
    );
    addTearDown(c.dispose);
    expect(c.files, isEmpty);
    expect(await c.create('Pitch'), 'home/ann/Pitch.qslide');
  });
}

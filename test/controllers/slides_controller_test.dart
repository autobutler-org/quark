import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/slides_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/utils/error_text.dart';

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

  group('importing PowerPoint (#1171)', () {
    const imported = (
      path: 'users/ann/Talk.qslide',
      slides: 3,
      warnings: <({int slide, String message})>[],
    );

    test('from the Quark imports the chosen file in place', () async {
      final calls = <String>[];
      final c = SlidesController(
        peekSlides: () => null,
        listSlides: () async => const [],
        importPowerPoint: (path, {serial}) async {
          calls.add(path);
          return imported;
        },
        uploadPowerPoint: (_) async => fail('nothing is uploaded'),
      );
      addTearDown(c.dispose);
      expect(await c.importFromQuark('talks/Talk.pptx'), imported);
      expect(calls, ['talks/Talk.pptx']);
    });

    test('from this device uploads the file, then imports where it '
        'landed', () async {
      final calls = <String>[];
      final c = SlidesController(
        peekSlides: () => null,
        listSlides: () async => const [],
        uploadPowerPoint: (pick) async {
          calls.add('upload ${pick.name}');
          return 'users/ann/Talk (1).pptx';
        },
        importPowerPoint: (path, {serial}) async {
          calls.add('import $path');
          return imported;
        },
      );
      addTearDown(c.dispose);
      final result = await c.importFromDevice((
        name: 'Talk.pptx',
        length: 1,
        bytes: () => Stream.value([1]),
      ));
      expect(result, imported);
      expect(calls, ['upload Talk.pptx', 'import users/ann/Talk (1).pptx']);
    });

    test('a failed upload is not imported and rethrows', () async {
      var imports = 0;
      final c = SlidesController(
        peekSlides: () => null,
        listSlides: () async => const [],
        uploadPowerPoint: (_) async => throw Exception('down'),
        importPowerPoint: (path, {serial}) async {
          imports++;
          return imported;
        },
      );
      addTearDown(c.dispose);
      await expectLater(
        c.importFromDevice((
          name: 'Talk.pptx',
          length: 1,
          bytes: () => const Stream.empty(),
        )),
        throwsException,
      );
      expect(imports, 0);
    });

    test('a file that is not a PowerPoint file is refused before it is '
        'uploaded', () async {
      var uploads = 0;
      final c = SlidesController(
        peekSlides: () => null,
        listSlides: () async => const [],
        uploadPowerPoint: (_) async {
          uploads++;
          return 'x';
        },
      );
      addTearDown(c.dispose);
      await expectLater(
        c.importFromDevice((
          name: 'notes.txt',
          length: 1,
          bytes: () => const Stream.empty(),
        )),
        throwsA(
          isA<MessageException>().having(
            (e) => Errors.importPowerPoint(e),
            'message',
            Errors.notPowerPoint,
          ),
        ),
      );
      expect(uploads, 0);
    });
  });
}

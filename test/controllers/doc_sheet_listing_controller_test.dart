import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/doc_sheet_listing_controller.dart';
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

/// The state behind the Docs and Sheets pages: one type's listing, the other
/// type's for search, the name and content search, and creating a file.
void main() {
  DocSheetListingController docs({
    Map<String, List<FileNode>>? cached,
    Future<List<FileNode>> Function(String type)? fetch,
    Future<List<ContentSearchResult>> Function(String query)? search,
    UploadBytesFn? upload,
  }) {
    final c = DocSheetListingController(
      fileType: 'qdoc',
      otherType: 'qsheet',
      emptyFile: '{}',
      peekListing: (type) => cached?[type],
      fetchListing: fetch ?? (_) async => const [],
      searchContent: search ?? (_) async => const [],
      uploadBytes:
          upload ??
          (dir, name, bytes, {serial, overwrite = false, keepBoth = false}) =>
              fail('nothing is uploaded'),
      landingFolder: () => 'home/ann',
    );
    addTearDown(c.dispose);
    return c;
  }

  test('starts from the cached listings, then the refresh replaces them '
      '(#1780)', () async {
    final c = docs(
      cached: {
        'qdoc': [_node('cached.qdoc')],
        'qsheet': [_node('cached.qsheet')],
      },
      fetch: (type) async => [_node('fresh.$type')],
    );
    expect(c.hasListing, isTrue);
    expect(c.files.single.name, 'cached.qdoc');
    expect(c.others.single.name, 'cached.qsheet');

    var notified = 0;
    c.addListener(() => notified++);
    await c.refresh();
    expect(c.files.single.name, 'fresh.qdoc');
    expect(c.others.single.name, 'fresh.qsheet');
    expect(notified, 1);
  });

  test('nothing cached means no listing until the first refresh', () async {
    final c = docs(fetch: (type) async => [_node('a.$type')]);
    expect(c.hasListing, isFalse);
    expect(c.files, isEmpty);
    await c.refresh();
    expect(c.hasListing, isTrue);
    expect(c.files.single.name, 'a.qdoc');
  });

  test('a failed refresh keeps the listing and the next good one clears the '
      'error', () async {
    Object? failure = Exception('down');
    final c = docs(
      cached: {
        'qdoc': [_node('a.qdoc')],
      },
      fetch: (type) async {
        final f = failure;
        if (f != null) throw f;
        return [_node('b.$type')];
      },
    );
    await c.refresh();
    expect(c.error, same(failure));
    expect(c.files.single.name, 'a.qdoc');

    failure = null;
    await c.refresh();
    expect(c.error, isNull);
    expect(c.files.single.name, 'b.qdoc');
  });

  testWidgets('filters both types by name at once and searches contents once '
      'typing pauses', (tester) async {
    final queries = <String>[];
    final c = docs(
      cached: {
        'qdoc': [_node('plans/budget.qdoc'), _node('notes.qdoc')],
        'qsheet': [_node('budget.qsheet'), _node('travel.qsheet')],
      },
      search: (q) async {
        queries.add(q);
        return const [
          ContentSearchResult(
            deviceSerial: '',
            relPath: 'deep/q3.qsheet',
            snippet: '<b>budget</b>',
          ),
        ];
      },
    );

    expect(c.filtered, hasLength(2));
    expect(c.otherFiltered, isEmpty, reason: 'only shown while searching');

    c.setQuery('bud');
    c.setQuery('budget ');
    expect(c.filtered.single.name, 'budget.qdoc');
    expect(c.otherFiltered.single.name, 'budget.qsheet');
    expect(c.contentSearching, isTrue);
    await tester.pump(DocSheetListingController.searchDebounce);
    expect(queries, ['budget'], reason: 'typing is debounced and trimmed');
    expect(c.contentSearching, isFalse);
    expect(c.contentResults.single.relPath, 'deep/q3.qsheet');

    c.setQuery('');
    expect(c.filtered, hasLength(2));
    expect(c.otherFiltered, isEmpty);
    expect(c.contentResults, isEmpty);
    expect(c.contentSearching, isFalse);
  });

  testWidgets('a failed content search still ends the search', (tester) async {
    final c = docs(search: (_) async => throw Exception('down'));
    c.setQuery('plan');
    await tester.pump(DocSheetListingController.searchDebounce);
    expect(c.contentSearching, isFalse);
    expect(c.contentResults, isEmpty);
  });

  test('create writes the empty file into the landing folder and returns '
      'where it landed', () async {
    final calls = <String>[];
    final c = docs(
      upload:
          (
            dir,
            name,
            bytes, {
            serial,
            overwrite = false,
            keepBoth = false,
          }) async {
            calls.add('$dir/$name ${String.fromCharCodes(bytes)}');
            return ['$dir/$name'];
          },
    );
    expect(await c.create('Plan'), 'home/ann/Plan.qdoc');
    expect(await c.create('Plan.qdoc'), 'home/ann/Plan.qdoc');
    expect(calls, ['home/ann/Plan.qdoc {}', 'home/ann/Plan.qdoc {}']);
  });

  test('siblings for a rename span both types', () {
    final c = docs(
      cached: {
        'qdoc': [_node('a.qdoc')],
        'qsheet': [_node('a.qsheet')],
      },
    );
    expect(c.siblings.map((n) => n.name), ['a.qdoc', 'a.qsheet']);
  });
}

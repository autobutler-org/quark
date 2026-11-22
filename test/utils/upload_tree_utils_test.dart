import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/utils/upload_tree_utils.dart';

/// Regression coverage for #1614 and #1615.
///
/// The invariant both hang on: a file picked or dropped inside a folder lands
/// at the same relative path on the server, and the directory it travels in is
/// the sanitized rootDir — never the multipart filename, which the backend
/// strips on purpose (the #1603 collision).
void main() {
  // Built with paths rather than names on purpose: XFile's dart:io
  // implementation ignores the `name` argument and derives the name from the
  // path, while the web implementation — the one that actually runs this code
  // — honours it. Passing a path is the form that means the same thing on
  // both, so these fixtures describe the web's items without lying about them.
  DropItemFile file(String name) => DropItemFile.fromData(_bytes, path: name);

  DropItemDirectory dir(String name, List<DropItem> children) =>
      DropItemDirectory('/$name', children, name: name);

  DropFlattenResult flatten(
    List<DropItem> items, {
    int maxDepth = kMaxUploadDepth,
    int maxFiles = kMaxUploadFiles,
  }) {
    return flattenDroppedItems(
      items,
      maxDepth: maxDepth,
      maxFiles: maxFiles,
      buildUpload: (f, name) async =>
          http.MultipartFile.fromBytes('files', _bytes, filename: name),
    );
  }

  group('sanitizeRelativeDir', () {
    test('keeps an ordinary nested path', () {
      expect(sanitizeRelativeDir('photos/2024'), 'photos/2024');
    });

    test('collapses empty, dot and whitespace segments', () {
      expect(sanitizeRelativeDir('/photos//2024/'), 'photos/2024');
      expect(sanitizeRelativeDir('photos/./2024'), 'photos/2024');
      expect(sanitizeRelativeDir('  photos / 2024 '), 'photos/2024');
      expect(sanitizeRelativeDir('photos/   /2024'), 'photos/2024');
    });

    test('normalizes Windows separators', () {
      expect(sanitizeRelativeDir(r'photos\2024'), 'photos/2024');
    });

    test('returns the root for an empty path', () {
      expect(sanitizeRelativeDir(''), '');
      expect(sanitizeRelativeDir('/'), '');
    });

    test('refuses traversal rather than cleaning it up', () {
      // Rejected, not sanitized to 'etc': a caller must drop the file, because
      // "the user meant photos/etc" is a guess and this is the value that
      // becomes rootDir on the server.
      expect(sanitizeRelativeDir('../etc'), isNull);
      expect(sanitizeRelativeDir('photos/../../etc'), isNull);
      expect(sanitizeRelativeDir('..'), isNull);
      expect(sanitizeRelativeDir(r'..\etc'), isNull);
    });
  });

  group('relativeDirOf', () {
    test('returns the directory part', () {
      expect(relativeDirOf('photos/2024/a.jpg'), 'photos/2024');
    });

    test('returns the root for a bare file name', () {
      expect(relativeDirOf('a.jpg'), '');
    });
  });

  group('uploadTargetPath', () {
    test('joins the relative directory onto the upload path', () {
      expect(uploadTargetPath('/docs', 'photos/2024'), '/docs/photos/2024');
    });

    test('leaves the upload path alone at the root', () {
      expect(uploadTargetPath('/docs', ''), '/docs');
      expect(uploadTargetPath('', ''), '');
    });
  });

  group('flattenDroppedItems', () {
    test('walks into a dropped folder instead of skipping it', () {
      // The #1614 repro: DropItemDirectory is a sibling of DropItemFile, not a
      // subtype, so an `is! DropItemFile` filter discarded the whole folder
      // and reported "No files to upload" while holding the files.
      final result = flatten([
        dir('photos', [
          dir('2024', [file('a.jpg'), file('b.jpg')]),
          file('cover.png'),
        ]),
      ]);

      expect(
        result.uploads.map((u) => '${u.relativeDir}|${u.name}'),
        containsAll([
          'photos/2024|a.jpg',
          'photos/2024|b.jpg',
          'photos|cover.png',
        ]),
      );
      expect(result.truncated, isFalse);
      expect(result.skippedTooDeep, 0);
    });

    test('a drop that lists the same file twice uploads it once', () {
      // The #4381 repro: a drag from the browser's downloads menu reached the
      // app with the one file listed twice, so it uploaded twice and a name
      // clash raised two conflict dialogs.
      final result = flatten([
        file('report.pdf'),
        file('report.pdf'),
        dir('photos', [file('a.jpg'), file('a.jpg')]),
      ]);

      expect(result.uploads.map((u) => '${u.relativeDir}|${u.name}'), [
        '|report.pdf',
        'photos|a.jpg',
      ]);
    });

    test('still handles loose files at the drop root', () {
      final result = flatten([file('notes.txt')]);

      expect(result.uploads, hasLength(1));
      expect(result.uploads.single.relativeDir, '');
      expect(result.uploads.single.name, 'notes.txt');
    });

    test('a drop with no chunk opener still produces uploads', () {
      // The optional half of #1629: a caller that only knows how to build a
      // whole multipart file keeps working, and its files take the
      // single-request path however large they are.
      final result = flatten([file('notes.txt')]);

      expect(result.uploads.single.openChunkSource, isNull);
    });

    test('threads a chunk opener through to each file', () {
      final opened = <String>[];
      final result = flattenDroppedItems(
        [
          dir('photos', [file('a.jpg')]),
          file('b.jpg'),
        ],
        buildUpload: (f, name) async =>
            http.MultipartFile.fromBytes('files', _bytes, filename: name),
        openChunkSource: (f) async {
          opened.add(f.name);
          return null;
        },
      );

      expect(result.uploads, hasLength(2));
      for (final upload in result.uploads) {
        expect(upload.openChunkSource, isNotNull);
      }

      // Deferred, like build: nothing is opened by walking the tree.
      expect(opened, isEmpty);
    });

    test('files land where the folder said they were', () {
      final result = flatten([
        dir('photos', [
          dir('2024', [file('a.jpg')]),
        ]),
      ]);

      final upload = result.uploads.single;
      expect(
        uploadTargetPath('/vacation', upload.relativeDir),
        '/vacation/photos/2024',
      );
    });

    test('stops at the depth cap rather than recursing forever', () {
      var deepest = dir('leaf', [file('deep.txt')]);
      for (var i = 0; i < 6; i++) {
        deepest = dir('level$i', [deepest]);
      }

      final result = flatten([deepest], maxDepth: 3);

      expect(result.uploads, isEmpty);
      expect(result.skippedTooDeep, 1);
    });

    test('stops at the file cap and says so', () {
      final result = flatten([
        dir('bulk', List.generate(10, (i) => file('f$i.txt'))),
      ], maxFiles: 4);

      expect(result.uploads, hasLength(4));
      expect(result.truncated, isTrue);
    });

    test('drops a folder whose name would escape the upload root', () {
      final result = flatten([
        dir('..', [file('escape.txt')]),
      ]);

      expect(result.uploads, isEmpty);
    });

    test('skips an unnamed file rather than uploading a blank name', () {
      final result = flatten([file('   ')]);

      expect(result.uploads, isEmpty);
    });

    test('builds each multipart file only when asked', () async {
      var built = 0;
      final result = flattenDroppedItems(
        [
          dir('photos', [file('a.jpg'), file('b.jpg')]),
        ],
        buildUpload: (f, name) async {
          built++;
          return http.MultipartFile.fromBytes('files', _bytes, filename: name);
        },
      );

      // Nothing is read up front — a folder upload cannot hold every file's
      // bytes at once.
      expect(built, 0);

      await result.uploads.first.build();
      expect(built, 1);
    });
  });

  group('groupByRelativeDir', () {
    test('one group per directory, in encounter order', () {
      final result = flatten([
        dir('photos', [
          dir('2024', [file('a.jpg'), file('b.jpg')]),
          file('cover.png'),
        ]),
      ]);

      final grouped = groupByRelativeDir(result.uploads);

      expect(grouped.keys, ['photos/2024', 'photos']);
      expect(grouped['photos/2024'], hasLength(2));
      expect(grouped['photos'], hasLength(1));
    });
  });
}

final _bytes = Uint8List.fromList([1, 2, 3]);

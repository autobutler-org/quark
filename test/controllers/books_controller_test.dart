import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/books_controller.dart';
import 'package:quark/models/file_node.dart';

FileNode _node(String path) => FileNode(
  name: path.split('/').last,
  size: 1,
  isDir: false,
  deviceName: '',
  devicePath: '',
  deviceSerial: '',
  dirPath: path,
);

/// The Books page's state (#1678): the listing, by title, and what a failed
/// refresh leaves behind.
void main() {
  test('lists books by title, whatever folder they are in', () async {
    final c = BooksController(
      listBooks: () async => [
        _node('a/zebra.pdf'),
        _node('z/Apple.epub'),
        _node('manual.pdf'),
      ],
    );
    addTearDown(c.dispose);
    expect(c.books, isEmpty);

    var notified = 0;
    c.addListener(() => notified++);
    await c.refresh();

    expect(c.books.map((b) => b.name), [
      'Apple.epub',
      'manual.pdf',
      'zebra.pdf',
    ]);
    expect(c.error, isNull);
    expect(notified, 1);
  });

  test(
    'a failed refresh keeps the listing and the next one clears the error',
    () async {
      Object? failure;
      final c = BooksController(
        listBooks: () async {
          final f = failure;
          if (f != null) throw f;
          return [_node('a.pdf')];
        },
      );
      addTearDown(c.dispose);
      await c.refresh();

      failure = Exception('down');
      await c.refresh();
      expect(c.error, same(failure));
      expect(c.books.single.name, 'a.pdf');

      failure = null;
      await c.refresh();
      expect(c.error, isNull);
    },
  );

  test('a refresh that lands after dispose notifies nobody', () async {
    final c = BooksController(listBooks: () async => [_node('a.pdf')]);
    final pending = c.refresh();
    c.dispose();
    await pending;
  });
}

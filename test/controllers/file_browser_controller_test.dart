import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_node.dart';

FileNode _node(String path, {String serial = '', bool isDir = false}) {
  final name = path.split('/').last;
  return FileNode(
    name: isDir ? '$name/' : name,
    size: 0,
    isDir: isDir,
    deviceName: '',
    devicePath: '',
    deviceSerial: serial,
    dirPath: path,
  );
}

void main() {
  group('deleteNodes', () {
    test('batches by device and parent folder', () async {
      final batches = <String>[];
      final controller = FileBrowserController(
        deleteFiles: (paths, {rootDir, deviceSerial}) async {
          batches.add('$deviceSerial|$rootDir|${paths.join(',')}');
        },
      );

      // A selection spanning folders, as search results and the unified view
      // produce: every name must land in its own folder, not the first one's.
      await controller.deleteNodes(
        nodes: [
          _node('Docs/a.txt'),
          _node('Photos/b.jpg'),
          _node('Docs/c.txt'),
          _node('top.txt'),
          _node('Docs/old', isDir: true),
          _node('Docs/a.txt', serial: 'USB1'),
        ],
      );

      expect(batches, [
        'null|Docs|a.txt,c.txt,old',
        'null|Photos|b.jpg',
        'null||top.txt',
        'USB1|Docs|a.txt',
      ]);
    });

    test('sends nothing for an empty selection', () async {
      var called = false;
      final controller = FileBrowserController(
        deleteFiles: (_, {rootDir, deviceSerial}) async => called = true,
      );

      await controller.deleteNodes(nodes: const []);

      expect(called, isFalse);
    });
  });
}

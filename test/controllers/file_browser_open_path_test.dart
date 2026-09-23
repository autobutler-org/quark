import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_node.dart';

FileNode _node({
  required String name,
  required String dirPath,
  required bool isDir,
}) {
  return FileNode(
    name: name,
    size: 0,
    isDir: isDir,
    deviceName: '',
    devicePath: '',
    deviceSerial: '',
    dirPath: dirPath,
  );
}

void main() {
  const controller = FileBrowserController();

  group('nextPathForOpenDirectory', () {
    // A row still painted from the parent listing must not be joined onto
    // the path the dialog already has (#2075).
    test('a directory opens at its own path, not a doubled name', () {
      expect(
        controller.nextPathForOpenDirectory(
          currentPath: '/UX Pass',
          node: _node(name: 'UX Pass', dirPath: 'UX Pass', isDir: true),
        ),
        '/UX Pass',
      );
    });

    test('a nested directory opens at the path the listing gave it', () {
      expect(
        controller.nextPathForOpenDirectory(
          currentPath: '/',
          node: _node(name: 'nested', dirPath: 'UX Pass/nested', isDir: true),
        ),
        '/UX Pass/nested',
      );
    });

    test('a file still joins its name onto the current path', () {
      expect(
        controller.nextPathForOpenDirectory(
          currentPath: '/Inbox',
          node: _node(
            name: 'notes.txt',
            dirPath: 'UX Pass/notes.txt',
            isDir: false,
          ),
        ),
        '/Inbox/notes.txt',
      );
    });
  });
}

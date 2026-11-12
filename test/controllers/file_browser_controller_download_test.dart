import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';

const _node = FileNode(
  name: 'a.txt',
  size: 0,
  isDir: false,
  deviceName: '',
  devicePath: '',
  deviceSerial: '',
  dirPath: '/a.txt',
);

void main() {
  testWidgets('a canceled save reports nothing', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    Future<FileMenuActionOutcome?> run(String? saved) =>
        FileBrowserController(
          saveNode: ({required node}) async => saved,
        ).handleFileAction(
          node: _node,
          action: FileMenuAction.download,
          context: context,
        );

    expect(await run(null), isNull);
    expect((await run('/saved/a.txt'))?.message, 'Downloaded a.txt');
  });

  test('a canceled archive or bytes save reports nothing', () async {
    final canceled = FileBrowserController(
      saveArchiveFile: (archive, entry, {serial, fileName}) async => null,
      saveBytesToFile: (bytes, name) async => null,
    );
    expect(
      await canceled.saveArchiveEntry('/z.zip', 'a.txt', name: 'a.txt'),
      isNull,
    );
    expect(await canceled.saveBytes(Uint8List(0), 'a.txt'), isNull);

    final saved = FileBrowserController(
      saveArchiveFile: (archive, entry, {serial, fileName}) async => '/x',
      saveBytesToFile: (bytes, name) async => '/x',
    );
    expect(
      await saved.saveArchiveEntry('/z.zip', 'a.txt', name: 'a.txt'),
      'Downloaded a.txt',
    );
    expect(await saved.saveBytes(Uint8List(0), 'a.txt'), 'Downloaded a.txt');
  });
}

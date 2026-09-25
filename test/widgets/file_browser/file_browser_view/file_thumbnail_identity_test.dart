import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_browser_list_tile.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_grid_preview.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_list_leading.dart';

FileNode _image(String name) => FileNode(
  name: name,
  size: 128,
  isDir: false,
  deviceName: 'Quark',
  devicePath: '',
  deviceSerial: '',
  dirPath: '',
);

/// The test binding answers every request with HTTP 400, and a shimmer keeps
/// a frame scheduled. Unmount, then fail if an image error escaped.
Future<void> _finish(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _pumpLeadings(WidgetTester tester, List<String> names) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            for (final name in names) FileListLeading(item: _image(name)),
          ],
        ),
      ),
    ),
  );
}

Finder _imageKey(String path) => find.byWidgetPredicate(
  (widget) => widget is CachedNetworkImage && widget.key == ValueKey(path),
);

void main() {
  testWidgets('swapping two image rows keeps each thumbnail on its own file', (
    tester,
  ) async {
    await _pumpLeadings(tester, ['mountain.png', 'sunset.png']);

    // Absent keys fail here: nothing is tagged with the file path.
    expect(find.byKey(const ValueKey('mountain.png')), findsOneWidget);
    expect(find.byKey(const ValueKey('sunset.png')), findsOneWidget);
    final mountain = tester.element(find.byKey(const ValueKey('mountain.png')));
    final sunset = tester.element(find.byKey(const ValueKey('sunset.png')));
    expect(mountain, isNot(same(sunset)));

    await _pumpLeadings(tester, ['sunset.png', 'mountain.png']);

    expect(find.byKey(const ValueKey('sunset.png')), findsOneWidget);
    expect(find.byKey(const ValueKey('mountain.png')), findsOneWidget);

    final first = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: find.byType(FileListLeading).first,
        matching: _imageKey('sunset.png'),
      ),
    );
    expect(first.imageUrl, contains('sunset.png'));
    expect(first.imageUrl, isNot(contains('mountain.png')));

    // The slot Flutter reused must not still be the previous file's element.
    expect(
      tester.element(find.byKey(const ValueKey('sunset.png'))),
      isNot(same(mountain)),
    );
    expect(
      tester.element(find.byKey(const ValueKey('mountain.png'))),
      isNot(same(sunset)),
    );

    await _finish(tester);
  });

  testWidgets('a list tile keys its leading by the file path', (tester) async {
    Future<void> pump(List<String> names) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final name in names)
                  FileBrowserListTile(
                    item: _image(name),
                    isSelected: false,
                    extractingPaths: const {},
                    showFileSizeAndMenu: false,
                    inArchive: false,
                    isSearchMode: false,
                    selectionMode: false,
                    onDispatchMenuAction: (_, _, _) {},
                    onOpenDirectory: (_) {},
                  ),
              ],
            ),
          ),
        ),
      );
    }

    await pump(['mountain.png', 'sunset.png']);
    await pump(['sunset.png', 'mountain.png']);

    final leadings = tester
        .widgetList<FileListLeading>(find.byType(FileListLeading))
        .toList();
    expect(leadings, hasLength(2));
    expect(leadings.first.key, const ValueKey('sunset.png'));
    expect(leadings.last.key, const ValueKey('mountain.png'));
    expect(_imageKey('sunset.png'), findsOneWidget);
    expect(_imageKey('mountain.png'), findsOneWidget);

    await _finish(tester);
  });

  testWidgets('swapping two grid previews keeps each thumbnail on its file', (
    tester,
  ) async {
    Future<void> pump(List<String> names) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final name in names)
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: FileGridPreview(item: _image(name)),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    await pump(['mountain.png', 'sunset.png']);
    final mountain = tester.element(find.byKey(const ValueKey('mountain.png')));

    await pump(['sunset.png', 'mountain.png']);

    expect(find.byKey(const ValueKey('sunset.png')), findsOneWidget);
    expect(find.byKey(const ValueKey('mountain.png')), findsOneWidget);
    final first = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: find.byType(FileGridPreview).first,
        matching: _imageKey('sunset.png'),
      ),
    );
    expect(first.key, const ValueKey('sunset.png'));
    expect(first.imageUrl, contains('sunset.png'));
    expect(
      tester.element(find.byKey(const ValueKey('sunset.png'))),
      isNot(same(mountain)),
    );

    await _finish(tester);
  });
}

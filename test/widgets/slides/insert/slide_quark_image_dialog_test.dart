import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/widgets/slides/insert/slide_image_upload_status.dart';
import 'package:quark/widgets/slides/insert/slide_quark_image_dialog.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;

/// Picking a picture already on the Quark for a slide (#1158).
void main() {
  FileNode node(String dir, String name, {bool isDir = false}) => FileNode(
    name: name,
    size: 1,
    isDir: isDir,
    deviceName: '',
    devicePath: '',
    deviceSerial: '',
    dirPath: dir.isEmpty ? name : '$dir/$name',
  );

  late List<String> listed;
  late Object? failure;

  Future<List<FileNode>> list(String path) async {
    listed.add(path);
    final f = failure;
    if (f != null) throw f;
    return [
      node(path, 'trips', isDir: true),
      node(path, 'dog.jpg'),
      node(path, 'notes.txt'),
    ];
  }

  setUp(() {
    listed = [];
    failure = null;
  });

  Future<String?> open(WidgetTester tester, {String start = 'talks'}) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => result = await SlideQuarkImageDialog.show(
                context,
                startPath: start,
                listFolder: list,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('lists folders and pictures, opens a folder, climbs back '
        'up, and picks a picture ($name)', (tester) async {
      tap.setViewport(tester, size);
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async =>
                    picked = await SlideQuarkImageDialog.show(
                      context,
                      startPath: '/talks/',
                      listFolder: list,
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(listed, ['talks']);
      expect(
        find.byKey(const ValueKey('slide_quark_image_file_notes.txt')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('slide_quark_image_folder_trips')),
      );
      await tester.pumpAndSettle();
      expect(listed.last, 'talks/trips');
      await tester.tap(find.byKey(const ValueKey('slide_quark_image_up')));
      await tester.pumpAndSettle();
      expect(listed.last, 'talks');
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('slide_quark_image_file_dog.jpg')),
      );
      await tester.pumpAndSettle();
      expect(picked, 'talks/dog.jpg');
    });
  }

  testWidgets('a failed listing says so and tries again', (tester) async {
    failure = Exception('boom');
    await open(tester);
    expect(find.text("Couldn't list this folder."), findsOneWidget);
    failure = null;
    await tester.tap(find.byKey(const ValueKey('slide_quark_image_retry')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('slide_quark_image_file_dog.jpg')),
      findsOneWidget,
    );
  });

  testWidgets('Up is off at the files root', (tester) async {
    await open(tester, start: '');
    final up = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey('slide_quark_image_up')),
        matching: find.byType(IconButton),
      ),
    );
    expect(up.onPressed, isNull);
  });

  testWidgets('the upload strip names the file and its progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: const Scaffold(
          body: SlideImageUploadStatus(name: 'dog.jpg', progress: 0.4),
        ),
      ),
    );
    expect(find.text('Uploading dog.jpg'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.4,
    );
  });
}

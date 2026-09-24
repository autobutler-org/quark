import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/models/transcode_format.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_menu_button.dart';
import 'package:quark_icons/quark_icons.dart';

FileNode _node(String path, {bool isDir = false}) => FileNode(
  name: path.split('/').last,
  size: 0,
  isDir: isDir,
  deviceName: '',
  devicePath: '',
  deviceSerial: 'SN1',
  dirPath: path,
);

/// The Files menu offers Convert video on a video file and runs the viewer's
/// flow through the controller (#2277).
void main() {
  final transcoded = <(String, String?)>[];

  Future<void> openMenu(
    WidgetTester tester,
    FileNode item, {
    bool inArchive = false,
  }) async {
    final controller = FileBrowserController(
      listTranscodeFormats: () async => const [
        TranscodeFormat(format: 'mp4', label: 'MP4'),
      ],
      transcodeVideo:
          (relPath, {serial, required format, required quality}) async {
            transcoded.add((relPath, serial));
            return 1;
          },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileMenuButton(
            menu: FileMenu(
              item: item,
              menuActions: FileBrowserView.defaultMenuActions,
              extractingPaths: const {},
              inArchive: inArchive,
              isSearchMode: false,
              onDispatchMenuAction: (context, node, action) =>
                  controller.handleFileAction(
                    node: node,
                    action: action,
                    context: context,
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(QuarkIcons.more_vert));
    await tester.pumpAndSettle();
  }

  setUp(transcoded.clear);

  testWidgets('picking Convert video queues the file through the flow', (
    tester,
  ) async {
    await openMenu(tester, _node('clips/trip.mov'));
    await tester.tap(find.text('Convert video'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transcode_format_mp4')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('transcode_convert')));
    await tester.pumpAndSettle();

    expect(transcoded, [('clips/trip.mov', 'SN1')]);
    expect(find.text('Conversion started'), findsOneWidget);
  });

  testWidgets('is not offered on a file that is not a video', (tester) async {
    await openMenu(tester, _node('docs/notes.txt'));
    expect(find.text('Convert video'), findsNothing);
  });

  testWidgets('is not offered on a folder', (tester) async {
    await openMenu(tester, _node('clips.mp4', isDir: true));
    expect(find.text('Convert video'), findsNothing);
  });

  testWidgets('is not offered inside an archive', (tester) async {
    await openMenu(tester, _node('clips/trip.mov'), inArchive: true);
    expect(find.text('Convert video'), findsNothing);
  });
}

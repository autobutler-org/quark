import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/file_viewer_actions.dart';

Future<void> _pumpAndDownload(
  WidgetTester tester,
  Future<String?> Function(String path, {String? serial, String? fileName})
  save,
) async {
  saveViewedFile = save;
  addTearDown(() => saveViewedFile = FilesService.saveFile);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => downloadViewedFile(
              context,
              path: 'a/b.txt',
              serial: null,
              name: 'b.txt',
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pump();
  await tester.pump();
}

/// The Download action's snack bar: a canceled save says nothing (#3160).
void main() {
  testWidgets('a canceled save shows no message', (tester) async {
    await _pumpAndDownload(tester, (path, {serial, fileName}) async => null);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a completed save reports the download', (tester) async {
    await _pumpAndDownload(
      tester,
      (path, {serial, fileName}) async => '/home/me/b.txt',
    );
    expect(find.text('Downloaded b.txt'), findsOneWidget);
  });

  testWidgets('a failed save reports an error, not the download', (
    tester,
  ) async {
    await _pumpAndDownload(
      tester,
      (path, {serial, fileName}) async => throw Exception('boom'),
    );
    expect(find.textContaining('Downloaded'), findsNothing);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}

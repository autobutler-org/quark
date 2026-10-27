import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/document_properties_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/generic_file_viewer_page.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// Office files opened in the generic viewer show the properties the file
/// saved about itself (#3275). A file with no properties endpoint does not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FileNode node(String name) => FileNode(
    name: name,
    size: 1200,
    isDir: false,
    deviceName: '',
    devicePath: '',
    deviceSerial: 'usb1',
    dirPath: 'docs/$name',
  );

  Future<void> pumpPage(
    WidgetTester tester, {
    required FileNode file,
    DocumentPropertiesController? properties,
    Size size = const Size(1280, 800),
  }) async {
    setViewport(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(
          QuarkThemeColor.classic.tokensFor(Brightness.dark),
          Brightness.dark,
        ),
        home: GenericFileViewerPage(
          node: file,
          propertiesController: properties,
        ),
      ),
    );
    await tester.pump();
  }

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('an office file shows its properties at ${size.width}', (
      tester,
    ) async {
      final controller = DocumentPropertiesController(
        path: 'docs/report.odp',
        loadProperties: (path, {serial}) async => const DocumentProperties(
          title: 'Quarterly report',
          author: 'Ada Lovelace',
          slides: 4,
          application: 'LibreOffice Impress',
          countsSource: 'saved',
        ),
      );
      addTearDown(controller.dispose);

      await pumpPage(
        tester,
        file: node('report.odp'),
        properties: controller,
        size: size,
      );
      await tester.pumpAndSettle();

      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(
        find.text('Counts as last saved in LibreOffice Impress.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a file the properties endpoint does not read shows none', (
    tester,
  ) async {
    var calls = 0;
    final controller = DocumentPropertiesController(
      path: 'docs/notes.txt',
      loadProperties: (path, {serial}) async {
        calls++;
        return const DocumentProperties(title: 'should not show');
      },
    );
    addTearDown(controller.dispose);

    await pumpPage(tester, file: node('notes.txt'), properties: controller);
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('should not show'), findsNothing);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('a failed load says why and retries', (tester) async {
    var calls = 0;
    final controller = DocumentPropertiesController(
      path: 'docs/report.docx',
      loadProperties: (path, {serial}) async {
        calls++;
        if (calls == 1) throw const ApiException(500, 'boom');
        return const DocumentProperties(author: 'Ada Lovelace');
      },
    );
    addTearDown(controller.dispose);

    await pumpPage(tester, file: node('report.docx'), properties: controller);
    await tester.pumpAndSettle();

    expect(
      find.text(
        Errors.message(const ApiException(500, 'boom'), 'load the properties'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('boom'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('document_properties_retry')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });
}

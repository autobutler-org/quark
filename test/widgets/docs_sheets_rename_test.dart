import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/rename_doc_sheet.dart';
import 'package:quark/widgets/docs/docs_body.dart';
import 'package:quark/widgets/sheets/sheets_body.dart';

/// #2056: a sheet or doc could only be renamed from Files → Move/Rename.
void main() {
  FileNode node(String path, {String serial = ''}) => FileNode(
    name: path.split('/').last,
    size: 1,
    isDir: false,
    deviceName: 'Data',
    devicePath: '',
    deviceSerial: serial,
    dirPath: path,
  );

  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pump();
  }

  Widget sheetsBody({
    List<FileNode> files = const [],
    List<FileNode> docFiles = const [],
    List<ContentSearchResult> results = const [],
    String query = '',
    ValueChanged<FileNode>? onRename,
  }) => SheetsBody(
    loading: false,
    error: null,
    files: files,
    docFiles: docFiles,
    contentResults: results,
    contentSearching: false,
    searchQuery: query,
    onRetry: () {},
    onCreateNew: () {},
    onOpenSheet: (_) {},
    onOpenDoc: (_) {},
    onRename: onRename,
  );

  testWidgets('a sheet row offers Rename and hands back its file', (
    tester,
  ) async {
    FileNode? renamed;
    final budget = node('reports/budget.qsheet');
    await pump(
      tester,
      sheetsBody(files: [budget], onRename: (n) => renamed = n),
    );

    await tester.tap(
      find.byKey(const ValueKey('doc_sheet_menu_reports/budget.qsheet')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('doc_sheet_rename_reports/budget.qsheet')),
    );
    await tester.pumpAndSettle();

    expect(renamed, same(budget));
  });

  testWidgets('a doc row offers Rename on the Docs page', (tester) async {
    FileNode? renamed;
    final notes = node('notes.qdoc');
    await pump(
      tester,
      DocsBody(
        loading: false,
        error: null,
        files: [notes],
        sheetFiles: const [],
        contentResults: const [],
        contentSearching: false,
        searchQuery: '',
        onRetry: () {},
        onCreateNew: () {},
        onOpenDoc: (_) {},
        onOpenSheet: (_) {},
        onRename: (n) => renamed = n,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('doc_sheet_menu_notes.qdoc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(renamed, same(notes));
  });

  testWidgets('content-only hits and rows without onRename have no menu', (
    tester,
  ) async {
    await pump(
      tester,
      sheetsBody(
        query: 'budget',
        results: const [
          ContentSearchResult(
            deviceSerial: '',
            relPath: 'q1.qsheet',
            snippet: 'the <b>budget</b>',
          ),
        ],
        onRename: (_) {},
      ),
    );
    expect(find.byIcon(Icons.more_vert), findsNothing);

    await pump(tester, sheetsBody(files: [node('budget.qsheet')]));
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  group('renameDocOrSheet', () {
    final outcome = <bool>[];

    Future<void> open(
      WidgetTester tester,
      FileNode target,
      List<FileNode> siblings,
    ) async {
      outcome.clear();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => outcome.add(
                  await renameDocOrSheet(context, target, siblings: siblings),
                ),
                child: const Text('rename'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('rename'));
      await tester.pumpAndSettle();
    }

    testWidgets('prefills the name without its extension', (tester) async {
      final budget = node('reports/budget.qsheet');
      await open(tester, budget, [budget]);

      expect(find.text('Rename spreadsheet'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'budget',
      );

      // An unchanged name is not a rename.
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(outcome, [false]);
    });

    testWidgets('refuses a name another file in the folder has', (
      tester,
    ) async {
      final budget = node('reports/budget.qsheet');
      final taken = node('reports/Forecast.qsheet');
      await open(tester, budget, [budget, taken, node('forecast.qsheet')]);

      await tester.enterText(find.byType(TextField), 'forecast');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(outcome, [false]);
      expect(find.text(Errors.fileNameTaken), findsOneWidget);
    });
  });
}

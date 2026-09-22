import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/widgets/docs/docs_body.dart';
import 'package:quark/widgets/sheets/sheets_body.dart';

/// #2259: Docs listed only .qdoc filename matches and Sheets only .qsheet, and
/// every content hit — whatever its type — opened in the current page's
/// editor. Each page now lists the other type in its own section, and a
/// content hit opens the editor its extension names.
void main() {
  FileNode node(String name) => FileNode(
    name: name,
    size: 1,
    isDir: false,
    deviceName: '',
    devicePath: '',
    deviceSerial: '',
    dirPath: name,
  );

  ContentSearchResult hit(String relPath) =>
      ContentSearchResult(deviceSerial: '', relPath: relPath, snippet: 'q');

  const contentResults = [
    ContentSearchResult(
      deviceSerial: '',
      relPath: 'notes.qdoc',
      snippet: 'budget notes',
    ),
    ContentSearchResult(
      deviceSerial: '',
      relPath: 'budget.qsheet',
      snippet: 'budget row',
    ),
    // Indexed, but neither page's editor opens it.
    ContentSearchResult(
      deviceSerial: '',
      relPath: 'readme.txt',
      snippet: 'budget text',
    ),
  ];

  Future<void> pumpBody(WidgetTester tester, Widget body) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: body),
        ),
        GoRoute(
          path: '/docs/:path',
          builder: (_, state) =>
              Text('doc editor ${state.pathParameters['path']}'),
        ),
        GoRoute(
          path: '/sheets/:path',
          builder: (_, state) =>
              Text('sheet editor ${state.pathParameters['path']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
  }

  Widget sheetsBody({
    List<FileNode> files = const [],
    List<FileNode> docFiles = const [],
    List<ContentSearchResult> results = contentResults,
  }) => SheetsBody(
    loading: false,
    error: null,
    files: files,
    docFiles: docFiles,
    contentResults: results,
    contentSearching: false,
    searchQuery: 'budget',
    onRetry: () {},
    onCreateNew: () {},
    onOpenSheet: (_) {},
    onOpenDoc: (_) {},
  );

  Widget docsBody({
    List<FileNode> files = const [],
    List<FileNode> sheetFiles = const [],
    List<ContentSearchResult> results = contentResults,
  }) => DocsBody(
    loading: false,
    error: null,
    files: files,
    sheetFiles: sheetFiles,
    contentResults: results,
    contentSearching: false,
    searchQuery: 'budget',
    onRetry: () {},
    onCreateNew: () {},
    onOpenDoc: (_) {},
    onOpenSheet: (_) {},
  );

  testWidgets('Sheets lists doc matches in their own section', (tester) async {
    await pumpBody(tester, sheetsBody(docFiles: [node('budget plan.qdoc')]));

    expect(find.text('In Docs'), findsOneWidget);
    expect(find.text('budget plan'), findsOneWidget);
    expect(find.text('notes'), findsOneWidget);
    expect(find.text('budget'), findsOneWidget);
    expect(find.text('readme.txt'), findsNothing);

    // The sheet's own content match comes before the other type's section.
    expect(
      tester.getTopLeft(find.text('budget')).dy,
      lessThan(tester.getTopLeft(find.text('In Docs')).dy),
    );

    await tester.tap(find.text('notes'));
    await tester.pumpAndSettle();
    expect(find.text('doc editor notes.qdoc'), findsOneWidget);
  });

  testWidgets('Docs lists sheet matches in their own section', (tester) async {
    await pumpBody(tester, docsBody(sheetFiles: [node('budget 2026.qsheet')]));

    expect(find.text('In Sheets'), findsOneWidget);
    expect(find.text('budget 2026'), findsOneWidget);
    expect(find.text('readme.txt'), findsNothing);
    expect(
      tester.getTopLeft(find.text('notes')).dy,
      lessThan(tester.getTopLeft(find.text('In Sheets')).dy),
    );

    await tester.tap(find.text('budget'));
    await tester.pumpAndSettle();
    expect(find.text('sheet editor budget.qsheet'), findsOneWidget);
  });

  testWidgets('a hit of the other type alone is not an empty search', (
    tester,
  ) async {
    await pumpBody(tester, sheetsBody(results: [hit('only.qdoc')]));

    expect(find.byKey(const ValueKey('sheets_create_cta')), findsNothing);
    expect(find.text('In Docs'), findsOneWidget);

    await pumpBody(tester, docsBody(sheetFiles: [node('budget.qsheet')]));
    expect(find.byKey(const ValueKey('docs_create_cta')), findsNothing);
  });

  testWidgets('the empty state still shows when neither type matched', (
    tester,
  ) async {
    await pumpBody(tester, sheetsBody(results: [hit('readme.txt')]));
    expect(find.byKey(const ValueKey('sheets_create_cta')), findsOneWidget);

    await pumpBody(tester, docsBody(results: const []));
    expect(find.byKey(const ValueKey('docs_create_cta')), findsOneWidget);
  });
}

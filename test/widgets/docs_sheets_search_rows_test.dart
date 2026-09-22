import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/widgets/docs/docs_body.dart';
import 'package:quark/widgets/sheets/sheets_body.dart';
import 'package:quark_icons/quark_icons.dart';

/// #2272: a filename match and a content match for the same kind of file
/// looked like different files, a file matching both ways was listed twice,
/// and every row carried the device name even on a Quark with one storage
/// location.
void main() {
  FileNode node(String path, {String serial = '', String device = 'Data'}) =>
      FileNode(
        name: path.split('/').last,
        size: 1,
        isDir: false,
        deviceName: device,
        devicePath: '',
        deviceSerial: serial,
        dirPath: path,
      );

  ContentSearchResult hit(String relPath, {String serial = ''}) =>
      ContentSearchResult(
        deviceSerial: serial,
        relPath: relPath,
        snippet: 'the <b>budget</b> of $relPath',
      );

  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pump();
  }

  Widget docsBody({
    List<FileNode> files = const [],
    List<FileNode> sheetFiles = const [],
    List<ContentSearchResult> results = const [],
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

  Widget sheetsBody({
    List<FileNode> files = const [],
    List<FileNode> docFiles = const [],
    List<ContentSearchResult> results = const [],
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

  /// The decoration of the box behind every row's [icon].
  List<Decoration?> iconBoxes(WidgetTester tester, IconData icon) => [
    for (final element
        in find
            .descendant(of: find.byType(ListTile), matching: find.byIcon(icon))
            .evaluate())
      tester
          .widget<Container>(
            find
                .ancestor(
                  of: find.byWidget(element.widget),
                  matching: find.byType(Container),
                )
                .first,
          )
          .decoration,
  ];

  group('a content match looks like a filename match', () {
    testWidgets('for the page own type and the other type, on Docs', (
      tester,
    ) async {
      await pump(
        tester,
        docsBody(
          files: [node('work/plan budget.qdoc')],
          sheetFiles: [node('money/budget 2026.qsheet')],
          results: [hit('notes/meeting.qdoc'), hit('money/q1.qsheet')],
        ),
      );

      // Titles drop the extension either way.
      expect(find.text('plan budget'), findsOneWidget);
      expect(find.text('meeting'), findsOneWidget);
      expect(find.text('budget 2026'), findsOneWidget);
      expect(find.text('q1'), findsOneWidget);
      expect(find.text('meeting.qdoc'), findsNothing);
      expect(find.text('q1.qsheet'), findsNothing);

      // The location stays, and the snippet is extra.
      expect(find.text('notes'), findsOneWidget);
      expect(find.text('the budget of notes/meeting.qdoc'), findsOneWidget);

      final docBoxes = iconBoxes(tester, QuarkIcons.description_outlined);
      expect(docBoxes, hasLength(2));
      expect(docBoxes.first, docBoxes.last);
      final sheetBoxes = iconBoxes(tester, QuarkIcons.table_chart_outlined);
      expect(sheetBoxes, hasLength(2));
      expect(sheetBoxes.first, sheetBoxes.last);
    });

    testWidgets('for the page own type and the other type, on Sheets', (
      tester,
    ) async {
      await pump(
        tester,
        sheetsBody(
          files: [node('money/budget 2026.qsheet')],
          docFiles: [node('work/plan budget.qdoc')],
          results: [hit('money/q1.qsheet'), hit('notes/meeting.qdoc')],
        ),
      );

      expect(find.text('q1'), findsOneWidget);
      expect(find.text('meeting'), findsOneWidget);
      expect(find.text('money'), findsNWidgets(2));

      final sheetBoxes = iconBoxes(tester, QuarkIcons.table_chart_outlined);
      expect(sheetBoxes, hasLength(2));
      expect(sheetBoxes.first, sheetBoxes.last);
      final docBoxes = iconBoxes(tester, QuarkIcons.description_outlined);
      expect(docBoxes, hasLength(2));
      expect(docBoxes.first, docBoxes.last);
    });
  });

  group('a file matching by name and content is listed once', () {
    testWidgets('on Docs, for docs and for sheets', (tester) async {
      await pump(
        tester,
        docsBody(
          files: [node('work/budget.qdoc')],
          sheetFiles: [node('money/budget.qsheet')],
          results: [hit('work/budget.qdoc'), hit('money/budget.qsheet')],
        ),
      );

      expect(find.text('budget'), findsNWidgets(2));
      expect(find.text('Content matches'), findsNothing);
      // The filename row carries the content hit's snippet.
      expect(find.text('the budget of work/budget.qdoc'), findsOneWidget);
      expect(find.text('the budget of money/budget.qsheet'), findsOneWidget);
    });

    testWidgets('on Sheets, for sheets and for docs', (tester) async {
      await pump(
        tester,
        sheetsBody(
          files: [node('money/budget.qsheet')],
          docFiles: [node('work/budget.qdoc')],
          results: [hit('money/budget.qsheet'), hit('work/budget.qdoc')],
        ),
      );

      expect(find.text('budget'), findsNWidgets(2));
      expect(find.text('Content matches'), findsNothing);
      expect(find.text('the budget of work/budget.qdoc'), findsOneWidget);
      expect(find.text('the budget of money/budget.qsheet'), findsOneWidget);
    });

    testWidgets('the same path on another device is a different file', (
      tester,
    ) async {
      await pump(
        tester,
        docsBody(
          files: [node('work/budget.qdoc')],
          results: [hit('work/budget.qdoc', serial: 'usb1')],
        ),
      );

      expect(find.text('budget'), findsNWidgets(2));
      expect(find.text('Content matches'), findsOneWidget);
    });
  });

  group('the device name', () {
    testWidgets('is left out when every row is on one device', (tester) async {
      await pump(
        tester,
        docsBody(
          files: [node('work/plan budget.qdoc')],
          sheetFiles: [node('money/budget.qsheet')],
          results: [hit('notes/meeting.qdoc')],
        ),
      );
      expect(find.textContaining('Data'), findsNothing);
      expect(find.text('work'), findsOneWidget);

      await pump(
        tester,
        sheetsBody(
          files: [node('money/budget.qsheet')],
          docFiles: [node('work/plan budget.qdoc')],
        ),
      );
      expect(find.textContaining('Data'), findsNothing);
    });

    testWidgets('is shown when the rows span more than one device', (
      tester,
    ) async {
      await pump(
        tester,
        docsBody(
          files: [
            node('work/budget.qdoc'),
            node('work/budget.qdoc', serial: 'usb1', device: 'USB'),
          ],
        ),
      );
      expect(find.text('Data · work'), findsOneWidget);
      expect(find.text('USB · work'), findsOneWidget);

      await pump(
        tester,
        sheetsBody(
          files: [node('money/budget.qsheet')],
          docFiles: [node('work/plan.qdoc', serial: 'usb1', device: 'USB')],
        ),
      );
      expect(find.text('Data · money'), findsOneWidget);
      expect(find.text('USB · work'), findsOneWidget);
    });
  });
}

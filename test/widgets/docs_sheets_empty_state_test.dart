import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/docs/docs_body.dart';
import 'package:quark/widgets/sheets/sheets_body.dart';

/// #2044: both lists offered "Create new …" only when the library was empty,
/// so a search that matched nothing left the user with centered copy and a
/// toolbar icon somewhere else on screen — at the exact moment they knew what
/// they wanted and did not have it.
void main() {
  Future<void> pumpDocs(
    WidgetTester tester, {
    required String query,
    required VoidCallback onCreateNew,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocsBody(
            loading: false,
            error: null,
            files: const [],
            contentResults: const [],
            contentSearching: false,
            searchQuery: query,
            onRetry: () {},
            onCreateNew: onCreateNew,
            onOpenDoc: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpSheets(
    WidgetTester tester, {
    required String query,
    required VoidCallback onCreateNew,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SheetsBody(
            loading: false,
            error: null,
            files: const [],
            contentResults: const [],
            contentSearching: false,
            searchQuery: query,
            onRetry: () {},
            onCreateNew: onCreateNew,
            onOpenSheet: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty Docs library still leads with create', (tester) async {
    await pumpDocs(tester, query: '', onCreateNew: () {});

    expect(find.text('Create new doc'), findsOneWidget);
  });

  testWidgets('a Docs search with no hits offers create too', (tester) async {
    var creates = 0;
    await pumpDocs(tester, query: 'invoice', onCreateNew: () => creates++);

    expect(find.text('No docs match your search.'), findsOneWidget);
    final cta = find.byKey(const ValueKey('docs_create_cta'));
    expect(cta, findsOneWidget);

    await tester.tap(cta);
    await tester.pump();
    expect(creates, 1);
  });

  testWidgets('a Sheets search with no hits offers create too', (tester) async {
    var creates = 0;
    await pumpSheets(tester, query: 'budget', onCreateNew: () => creates++);

    expect(find.text('No sheets match your search.'), findsOneWidget);
    final cta = find.byKey(const ValueKey('sheets_create_cta'));
    expect(cta, findsOneWidget);

    await tester.tap(cta);
    await tester.pump();
    expect(creates, 1);
  });
}

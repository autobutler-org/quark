import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testWidgets('summarizes the search results', (tester) async {
    await pumpAt(
      tester,
      const FileBrowserHeader(
        isSearchMode: true,
        searchQuery: 'invoice',
        resultCount: 4,
      ),
    );

    expect(find.text("4 results for 'invoice'"), findsOneWidget);
  });

  testWidgets('says "result" for exactly one', (tester) async {
    await pumpAt(
      tester,
      const FileBrowserHeader(
        isSearchMode: true,
        searchQuery: 'invoice',
        resultCount: 1,
      ),
      size: narrowViewport,
    );

    expect(find.text("1 result for 'invoice'"), findsOneWidget);
  });

  testWidgets('reads as zero while the count is unknown', (tester) async {
    await pumpAt(
      tester,
      const FileBrowserHeader(isSearchMode: true, searchQuery: 'invoice'),
      size: wideViewport,
    );

    expect(find.text("0 results for 'invoice'"), findsOneWidget);
  });

  testWidgets('says it is searching while the query is pending', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const FileBrowserHeader(
        isSearchMode: true,
        isPending: true,
        searchQuery: 'mountain',
        resultCount: 4,
      ),
    );

    expect(find.text("Searching for 'mountain'…"), findsOneWidget);
    expect(find.textContaining('result'), findsNothing);
    expect(
      find.byKey(const ValueKey('file_header_close_search')),
      findsOneWidget,
    );
  });

  testWidgets('leaves search through its callback', (tester) async {
    var closes = 0;
    await pumpAt(
      tester,
      FileBrowserHeader(
        isSearchMode: true,
        searchQuery: 'invoice',
        resultCount: 0,
        onClose: () => closes++,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('file_header_close_search')));
    await tester.pump();

    expect(closes, 1);
  });

  testWidgets('renders nothing outside search mode', (tester) async {
    await pumpAt(tester, const FileBrowserHeader(isSearchMode: false));

    expect(find.byType(Text), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });
}

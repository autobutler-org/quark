import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('summarizes the search results', (tester, size) async {
    await pumpAt(
      tester,
      const FileBrowserHeader(
        isSearchMode: true,
        searchQuery: 'invoice',
        resultCount: 4,
      ),
      size: size,
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

  testBothViewports('says it is searching while the query is pending', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const FileBrowserHeader(
        isSearchMode: true,
        isPending: true,
        searchQuery: 'mountain',
        resultCount: 4,
      ),
      size: size,
    );

    expect(find.text("Searching for 'mountain'…"), findsOneWidget);
    expect(find.textContaining('result'), findsNothing);
    expect(
      find.byKey(const ValueKey('file_header_close_search')),
      findsOneWidget,
    );
  });

  testBothViewports('leaves search through its callback', (tester, size) async {
    var closes = 0;
    await pumpAt(
      tester,
      FileBrowserHeader(
        isSearchMode: true,
        searchQuery: 'invoice',
        resultCount: 0,
        onClose: () => closes++,
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('file_header_close_search')));
    await tester.pump();

    expect(closes, 1);
  });

  testBothViewports('renders nothing outside search mode', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const FileBrowserHeader(isSearchMode: false),
      size: size,
    );

    expect(find.byType(Text), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });
}

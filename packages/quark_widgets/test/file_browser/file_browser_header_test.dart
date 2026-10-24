import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  for (final (count, summary) in [
    (4, "4 results for 'invoice'"),
    (1, "1 result for 'invoice'"),
    (null, "0 results for 'invoice'"),
  ]) {
    testWidgets('summarizes ${count ?? 'an unknown number of'} results', (
      tester,
    ) async {
      await pumpAt(
        tester,
        FileBrowserHeader(
          isSearchMode: true,
          searchQuery: 'invoice',
          resultCount: count,
        ),
      );

      expect(find.text(summary), findsOneWidget);
    });
  }

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

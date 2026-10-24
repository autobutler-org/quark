import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// `QuarkCodeViewer` shows a text file read-only: every state it renders,
/// every callback, both wrap modes with a line far wider than a phone, and
/// the scroll that brings a search hit far down the file into view.
void main() {
  const lineKey = 'code_viewer_line_';
  const search = ValueKey('code_viewer_search_field');
  const previous = ValueKey('code_viewer_search_previous');
  const next = ValueKey('code_viewer_search_next');
  const wrapToggle = ValueKey('code_viewer_wrap_toggle');
  const loadMore = ValueKey('code_viewer_load_more');
  const counter = ValueKey('code_viewer_match_count');

  List<String> numbered(int count) => [
    for (var i = 0; i < count; i++) 'line number $i',
  ];

  /// A file where every tenth line is far wider than either viewport.
  List<String> ragged(int count) => [
    for (var i = 0; i < count; i++)
      i % 10 == 0 ? 'wide $i ${'word ' * 80}' : 'line $i',
  ];

  ScrollPosition verticalScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  testBothViewports('renders each line beside its number', (
    tester,
    size,
  ) async {
    const lines = ['void main() {', '  print("hi");', '}'];
    await pumpAt(
      tester,
      const QuarkCodeViewer(lines: lines, language: CodeLanguage.dart),
      size: size,
    );

    expect(tester.takeException(), isNull);
    for (var i = 0; i < lines.length; i++) {
      final line = find.byKey(ValueKey('$lineKey$i'));
      expect(line, findsOneWidget);
      expect(
        find.descendant(of: line, matching: find.text('${i + 1}')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: line,
          matching: find.text(lines[i], findRichText: true),
        ),
        findsOneWidget,
      );
    }
    expect(find.byKey(counter), findsNothing);
  });

  testWidgets('shows a loader while loading', (tester) async {
    await pumpAt(tester, const QuarkCodeViewer(lines: [], isLoading: true));

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.text('Empty file'), findsNothing);
    expect(find.byKey(search), findsOneWidget);
  });

  testWidgets('shows the error as given, and retries', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkCodeViewer(
        lines: const ['stale'],
        error: "Couldn't load the file.",
        onRetry: () => events.add('retry'),
      ),
    );

    expect(find.text("Couldn't load the file."), findsOneWidget);
    expect(find.byKey(const ValueKey('${lineKey}0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('code_viewer_retry')));
    expect(events, ['retry']);

    await pumpAt(tester, const QuarkCodeViewer(lines: [], error: 'Gone.'));
    expect(find.text('Gone.'), findsOneWidget);
    expect(find.byKey(const ValueKey('code_viewer_retry')), findsNothing);
  });

  testWidgets('says an empty file is empty', (tester) async {
    await pumpAt(tester, const QuarkCodeViewer(lines: []));

    expect(find.text('Empty file'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  testBothViewports('the wrap toggle reports the opposite of wrap', (
    tester,
    size,
  ) async {
    final changes = <bool>[];
    for (final wrap in [false, true]) {
      await pumpAt(
        tester,
        QuarkCodeViewer(
          lines: numbered(3),
          wrap: wrap,
          onWrapChanged: changes.add,
        ),
        size: size,
      );
      expect(
        tester.widget<QuarkBarIconButton>(find.byKey(wrapToggle)).selected,
        wrap,
      );
      await tester.tap(find.byKey(wrapToggle));
    }
    expect(changes, [true, false]);

    await pumpAt(tester, QuarkCodeViewer(lines: numbered(3)), size: size);
    expect(
      tester.widget<QuarkBarIconButton>(find.byKey(wrapToggle)).onPressed,
      isNull,
    );
  });

  testBothViewports('a very long line scrolls sideways with wrap off', (
    tester,
    size,
  ) async {
    await pumpAt(tester, QuarkCodeViewer(lines: ragged(40)), size: size);

    expect(tester.takeException(), isNull);
    final wide = tester.getSize(find.byKey(const ValueKey('${lineKey}0')));
    final short = tester.getSize(find.byKey(const ValueKey('${lineKey}1')));
    expect(wide.height, short.height);
    expect(wide.width, greaterThan(size.width));
    expectNoClippedText(tester);
  });

  testBothViewports('a very long line wraps with wrap on', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkCodeViewer(lines: ragged(40), wrap: true),
      size: size,
    );

    expect(tester.takeException(), isNull);
    final wide = tester.getSize(find.byKey(const ValueKey('${lineKey}0')));
    final short = tester.getSize(find.byKey(const ValueKey('${lineKey}1')));
    expect(wide.height, greaterThan(short.height));
    expect(wide.width, size.width);
    expectNoClippedText(tester);
  });

  testWidgets('typing in the search field reports the query', (tester) async {
    final queries = <String>[];
    await pumpAt(
      tester,
      QuarkCodeViewer(lines: numbered(3), onSearchChanged: queries.add),
    );

    await tester.enterText(find.byKey(search), 'number');
    expect(queries, ['number']);
  });

  testWidgets('the search field follows a query the caller changes', (
    tester,
  ) async {
    String fieldText() =>
        tester.widget<TextField>(find.byKey(search)).controller!.text;
    await pumpAt(
      tester,
      QuarkCodeViewer(lines: numbered(3), onSearchChanged: (_) {}),
    );
    expect(fieldText(), '');

    await pumpAt(
      tester,
      QuarkCodeViewer(
        lines: numbered(3),
        searchQuery: 'line',
        onSearchChanged: (_) {},
      ),
    );
    expect(fieldText(), 'line');

    // The caller is still on 'line' while the user types on: leave the field.
    await tester.enterText(find.byKey(search), 'line n');
    await pumpAt(
      tester,
      QuarkCodeViewer(
        lines: numbered(3),
        searchQuery: 'line',
        onSearchChanged: (_) {},
      ),
    );
    expect(fieldText(), 'line n');

    await pumpAt(
      tester,
      QuarkCodeViewer(lines: numbered(3), onSearchChanged: (_) {}),
    );
    expect(fieldText(), '');
  });

  testWidgets('next, previous and Enter step through the hits', (tester) async {
    final events = <String>[];
    final lines = numbered(3);
    await pumpAt(
      tester,
      QuarkCodeViewer(
        lines: lines,
        searchQuery: 'line',
        onSearchChanged: (_) {},
        matches: findCodeMatches(lines, 'line'),
        activeMatch: 0,
        onNextMatch: () => events.add('next'),
        onPreviousMatch: () => events.add('previous'),
      ),
    );

    await tester.tap(find.byKey(next));
    await tester.tap(find.byKey(previous));
    await tester.tap(find.byKey(search));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(events, ['next', 'previous', 'next']);
  });

  testWidgets('next and previous are disabled without a hit', (tester) async {
    await pumpAt(
      tester,
      QuarkCodeViewer(
        lines: numbered(3),
        searchQuery: 'absent',
        onNextMatch: () {},
        onPreviousMatch: () {},
      ),
    );

    for (final key in [previous, next]) {
      expect(
        tester.widget<QuarkBarIconButton>(find.byKey(key)).onPressed,
        isNull,
      );
    }
  });

  testBothViewports('a hit keeps its text above AA on the tint', (
    tester,
    size,
  ) async {
    const lines = ['// a comment', 'final s = "str" + 42;'];
    for (final themeColor in QuarkThemeColor.presets) {
      for (final brightness in Brightness.values) {
        await pumpAt(
          tester,
          QuarkCodeViewer(
            lines: lines,
            language: CodeLanguage.dart,
            searchQuery: 'x',
            matches: const [
              CodeSearchMatch(line: 0, start: 0, end: 12),
              CodeSearchMatch(line: 1, start: 0, end: 21),
            ],
          ),
          size: size,
          brightness: brightness,
          themeColor: themeColor,
        );
        // The app animates from the last theme to this one.
        await tester.pumpAndSettle();
        final tokens = themeColor.tokensFor(brightness);
        var hits = 0;
        for (final paragraph
            in tester
                .widgetList<RichText>(
                  find.descendant(
                    of: find.byKey(const ValueKey('${lineKey}0')),
                    matching: find.byType(RichText),
                  ),
                )
                .followedBy(
                  tester.widgetList<RichText>(
                    find.descendant(
                      of: find.byKey(const ValueKey('${lineKey}1')),
                      matching: find.byType(RichText),
                    ),
                  ),
                )) {
          paragraph.text.visitChildren((span) {
            final background = span.style?.backgroundColor;
            if (background == null) return true;
            hits++;
            final color = span.style!.color!;
            expect(
              contrastRatio(
                color,
                Color.alphaBlend(background, tokens.background),
              ),
              greaterThanOrEqualTo(4.5),
              reason:
                  '${themeColor.name} ${brightness.name}: '
                  '"${(span as TextSpan).text}"',
            );
            return true;
          });
        }
        expect(hits, greaterThan(0), reason: 'the hits are tinted');
      }
    }
    expect(tester.takeException(), isNull);
  });

  testBothViewports('the counter says where the search is', (
    tester,
    size,
  ) async {
    final lines = numbered(17);
    final matches = findCodeMatches(lines, 'line');
    String counterText() => tester.widget<Text>(find.byKey(counter)).data!;
    Future<void> pump({
      String query = 'line',
      List<CodeSearchMatch> hits = const [],
      int? active,
      bool hasMore = false,
    }) => pumpAt(
      tester,
      QuarkCodeViewer(
        lines: lines,
        searchQuery: query,
        matches: hits,
        activeMatch: active,
        hasMore: hasMore,
        isLoadingMore: hasMore,
        statusLabel: 'Showing 256 KB of 1.2 GB',
      ),
      size: size,
    );

    await pump(hits: matches, active: 2);
    expect(counterText(), '3 of 17');
    expect(find.text('Showing 256 KB of 1.2 GB'), findsOneWidget);

    await pump(hits: matches);
    expect(counterText(), '17 results');

    await pump(hits: matches.sublist(0, 1));
    expect(counterText(), '1 result');

    await pump(hits: matches, active: 2, hasMore: true);
    expect(counterText(), '3 of 17 loaded');

    await pump();
    expect(counterText(), 'No results');

    await pump(hasMore: true);
    expect(counterText(), 'No results in the loaded part');

    await pump(query: '');
    expect(find.byKey(counter), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final wrap in [false, true]) {
    final mode = wrap ? 'wrap on' : 'wrap off';

    testBothViewports('scrolls a hit far down the file into view, $mode', (
      tester,
      size,
    ) async {
      final lines = ragged(1000);
      const matches = [
        CodeSearchMatch(line: 3, start: 0, end: 4),
        CodeSearchMatch(line: 800, start: 0, end: 4),
        CodeSearchMatch(line: 999, start: 0, end: 4),
      ];
      Future<void> pump(int? active) async {
        await pumpAt(
          tester,
          QuarkCodeViewer(
            lines: lines,
            wrap: wrap,
            searchQuery: 'line',
            matches: matches,
            activeMatch: active,
          ),
          size: size,
        );
        await tester.pump();
      }

      void expectInView(int line) {
        final viewport = tester.getRect(find.byType(CustomScrollView));
        final finder = find.byKey(ValueKey('$lineKey$line'));
        expect(finder, findsOneWidget);
        final rect = tester.getRect(finder);
        expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.01));
        expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.01));
      }

      await pump(null);
      expect(find.byKey(const ValueKey('${lineKey}800')), findsNothing);

      await pump(1);
      expectInView(800);

      // The last line: the scroll stops at the end of the file, not past it.
      await pump(2);
      expectInView(999);
      final position = verticalScroll(tester);
      expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent));

      await pump(0);
      expectInView(3);

      // The same hit in a recomputed list must not pull the view back.
      verticalScroll(tester).jumpTo(5000);
      await tester.pump();
      await pumpAt(
        tester,
        QuarkCodeViewer(
          lines: lines,
          wrap: wrap,
          searchQuery: 'line',
          matches: [...matches],
          activeMatch: 0,
        ),
        size: size,
      );
      await tester.pump();
      expect(verticalScroll(tester).pixels, 5000);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens on the active hit, $mode', (tester) async {
      await pumpAt(
        tester,
        QuarkCodeViewer(
          lines: ragged(1000),
          wrap: wrap,
          matches: const [CodeSearchMatch(line: 640, start: 0, end: 4)],
          activeMatch: 0,
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('${lineKey}640')), findsOneWidget);
    });
  }

  testWidgets('scrolls sideways to a hit far along a line', (tester) async {
    final lines = ['short', 'x' * 900 + 'needle'];
    await pumpAt(
      tester,
      QuarkCodeViewer(
        lines: lines,
        matches: findCodeMatches(lines, 'needle'),
        activeMatch: 0,
      ),
      size: narrowViewport,
    );
    await tester.pump();

    final sideways = tester
        .state<ScrollableState>(
          find
              .ancestor(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(sideways.pixels, greaterThan(0));
  });

  testBothViewports('asks for more near the end, once for each length', (
    tester,
    size,
  ) async {
    var asked = 0;
    Future<void> pump(List<String> lines) => pumpAt(
      tester,
      QuarkCodeViewer(lines: lines, hasMore: true, onLoadMore: () => asked++),
      size: size,
    );

    await pump(numbered(500));
    expect(asked, 0, reason: 'the end is many viewports away');

    final position = verticalScroll(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(asked, 1);

    position.jumpTo(position.maxScrollExtent - 10);
    await tester.pump();
    expect(asked, 1, reason: 'the same lines ask once');

    await tester.tap(find.byKey(loadMore));
    expect(asked, 2, reason: 'the button always asks');

    await pump(numbered(520));
    await tester.pump();
    expect(asked, 3, reason: 'more lines arrived and the end is still near');
  });

  testWidgets('asks at once when the loaded part does not fill the view', (
    tester,
  ) async {
    var asked = 0;
    await pumpAt(
      tester,
      QuarkCodeViewer(
        lines: numbered(3),
        hasMore: true,
        onLoadMore: () => asked++,
      ),
    );
    expect(asked, 1);
  });

  testBothViewports('does not ask while loading more or after a failure', (
    tester,
    size,
  ) async {
    var asked = 0;
    await pumpAt(
      tester,
      QuarkCodeViewer(
        lines: numbered(500),
        hasMore: true,
        isLoadingMore: true,
        onLoadMore: () => asked++,
      ),
      size: size,
    );
    var position = verticalScroll(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(asked, 0);
    expect(find.byKey(loadMore), findsNothing);
    expect(find.byType(QuarkLoader), findsOneWidget);

    await pumpAt(
      tester,
      QuarkCodeViewer(
        lines: numbered(500),
        hasMore: true,
        loadMoreError: "Couldn't load more of the file.",
        onLoadMore: () => asked++,
      ),
      size: size,
    );
    position = verticalScroll(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(asked, 0);
    expect(find.text("Couldn't load more of the file."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(loadMore));
    expect(asked, 1);
  });

  testWidgets('shows no footer once the whole file is loaded', (tester) async {
    await pumpAt(tester, QuarkCodeViewer(lines: numbered(3)));
    expect(find.byKey(loadMore), findsNothing);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: token and hit colors come from the theme', (
      tester,
    ) async {
      const lines = ['return 42; // "x"', 'return "s";'];
      await pumpAt(
        tester,
        const QuarkCodeViewer(
          lines: lines,
          language: CodeLanguage.dart,
          matches: [
            CodeSearchMatch(line: 0, start: 7, end: 9),
            CodeSearchMatch(line: 1, start: 0, end: 6),
          ],
          activeMatch: 0,
        ),
        brightness: brightness,
      );

      /// The style of the span of [line] that reads [text].
      TextStyle? styleOf(int line, String text) {
        TextStyle? found;
        tester
            .widget<RichText>(
              find.descendant(
                of: find.byKey(ValueKey('$lineKey$line')),
                matching: find.text(lines[line], findRichText: true),
              ),
            )
            .text
            .visitChildren((span) {
              if (span is TextSpan && span.text == text) found = span.style;
              return found == null;
            });
        return found;
      }

      expect(styleOf(0, 'return')!.color, tokens.primary);
      expect(styleOf(0, '// "x"')!.color, tokens.mutedForeground);
      expect(styleOf(1, '"s"')!.color, tokens.success);
      // The active hit, on a number.
      expect(styleOf(0, '42')!.backgroundColor, tokens.primary);
      expect(styleOf(0, '42')!.color, tokens.primaryForeground);
      // Any other hit drops its token color for plain text on a tint.
      expect(styleOf(1, 'return')!.color, tokens.foreground);
      expect(
        styleOf(1, 'return')!.backgroundColor,
        tokens.primary.withValues(alpha: 0.25),
      );
    });
  }

  testWidgets('a hit with offsets outside its line does not throw', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const QuarkCodeViewer(
        lines: ['short', ''],
        matches: [
          CodeSearchMatch(line: 0, start: -4, end: 2),
          CodeSearchMatch(line: 0, start: 4, end: 90),
          CodeSearchMatch(line: 1, start: 3, end: 1),
          CodeSearchMatch(line: 7, start: 0, end: 1),
        ],
        activeMatch: 3,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a different file replaces what was worked out for the last', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const QuarkCodeViewer(
        lines: ['/* open', 'still comment'],
        language: CodeLanguage.c,
      ),
    );
    await pumpAt(
      tester,
      const QuarkCodeViewer(
        lines: ['int a;', 'return a;'],
        language: CodeLanguage.c,
      ),
    );

    final line = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('${lineKey}1')),
        matching: find.text('return a;', findRichText: true),
      ),
    );
    final colors = <Color?>[];
    line.text.visitChildren((span) {
      if (span is TextSpan && span.text == 'return') {
        colors.add(span.style?.color);
      }
      return true;
    });
    expect(colors, [QuarkTokens.dark.primary]);
  });

  testWidgets('every icon-only button carries a tooltip', (tester) async {
    await pumpAt(tester, QuarkCodeViewer(lines: numbered(3)));
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.tooltip, isNotNull, reason: 'an icon alone says nothing');
    }
    expect(find.byTooltip('Wrap lines'), findsOneWidget);
  });

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    final lines = numbered(40);
    await pumpAt(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: QuarkCodeViewer(
          lines: lines,
          searchQuery: 'line',
          onSearchChanged: (_) {},
          matches: findCodeMatches(lines, 'line'),
          activeMatch: 0,
          onNextMatch: () {},
          onPreviousMatch: () {},
          onWrapChanged: (_) {},
          hasMore: true,
          loadMoreError: 'Failed.',
          onLoadMore: () {},
        ),
      ),
      size: size,
    );
    await expectTapTargetGuidelines(tester);
  });

  for (final wrap in [false, true]) {
    testLargeText('lays out without clipping, wrap ${wrap ? 'on' : 'off'}', (
      tester,
      size,
    ) async {
      final lines = ragged(1000);
      await pumpAt(
        tester,
        QuarkCodeViewer(
          lines: lines,
          language: CodeLanguage.dart,
          wrap: wrap,
          onWrapChanged: (_) {},
          searchQuery: 'word',
          onSearchChanged: (_) {},
          matches: findCodeMatches(lines, 'word', limit: 17),
          activeMatch: 2,
          onNextMatch: () {},
          onPreviousMatch: () {},
          hasMore: true,
          loadMoreError: "Couldn't load more of the file.",
          onLoadMore: () {},
          statusLabel: 'Showing 256 KB of 1.2 GB',
        ),
        size: size,
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expectNoClippedText(tester);
      expect(find.text('3 of 17 loaded'), findsOneWidget);
    });
  }
}

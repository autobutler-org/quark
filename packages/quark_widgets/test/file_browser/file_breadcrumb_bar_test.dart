import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required String path,
    Size size = wideViewport,
    bool isSearchMode = false,
    List<String>? events,
  }) {
    void record(String e) => events?.add(e);
    return pumpAt(
      tester,
      FileBreadcrumbBar(
        currentPath: path,
        isSearchMode: isSearchMode,
        onGoHome: () => record('home'),
        onGoUp: () => record('up'),
        onPathSelected: (p) => record('select:$p'),
      ),
      size: size,
    );
  }

  testBothViewports('renders one segment per directory in the path', (
    tester,
    size,
  ) async {
    await pumpBar(tester, path: '/photos/2024/june', size: size);

    expect(find.text('photos'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('june'), findsOneWidget);
  });

  testBothViewports('navigates to the ancestor that was tapped', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpBar(
      tester,
      path: '/photos/2024/june',
      size: size,
      events: events,
    );

    await tester.tap(find.byKey(const ValueKey('breadcrumb_segment_0')));
    await tester.tap(find.byKey(const ValueKey('breadcrumb_segment_1')));
    await tester.pump();

    expect(events, ['select:/photos', 'select:/photos/2024']);
  });

  testBothViewports('leaves the current directory without a tap target', (
    tester,
    size,
  ) async {
    await pumpBar(tester, path: '/photos/2024/june', size: size);

    // Only the two ancestors get a key; the leaf is plain text.
    expect(find.byKey(const ValueKey('breadcrumb_segment_2')), findsNothing);
  });

  testBothViewports('goes home and up through its callbacks', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpBar(tester, path: '/photos', size: size, events: events);

    await tester.tap(find.byKey(const ValueKey('breadcrumb_home')));
    await tester.tap(find.byKey(const ValueKey('breadcrumb_up')));
    await tester.pump();

    expect(events, ['home', 'up']);
  });

  testWidgets('disables the up button at the root', (tester) async {
    await pumpBar(tester, path: '', size: narrowViewport);

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('breadcrumb_up')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('/'), findsOneWidget);
  });

  testBothViewports('disappears in search mode', (tester, size) async {
    await pumpBar(tester, path: '/photos', size: size, isSearchMode: true);

    expect(find.text('photos'), findsNothing);
    expect(find.byKey(const ValueKey('breadcrumb_up')), findsNothing);
  });

  testWidgets('scrolls a deep path instead of overflowing a narrow bar', (
    tester,
  ) async {
    await pumpBar(
      tester,
      path: '/a-very-long-directory-name/another-long-one/and-a-third/leaf',
      size: narrowViewport,
    );

    expect(tester.takeException(), isNull);
  });

  /// #2010: at the top folder the home glyph stayed primary-colored and
  /// tappable, and answered a click with nothing — the up button beside it
  /// had always gone quiet there.
  testBothViewports('the home glyph is inert at the top folder', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await pumpBar(tester, path: '', size: size, events: events);

    await tester.tap(find.byKey(const ValueKey('breadcrumb_home')));
    await tester.pump();

    expect(events, isEmpty);
    expect(find.byTooltip('You are in the top folder'), findsOneWidget);
  });

  testWidgets('the home glyph still goes home from a folder', (tester) async {
    final events = <String>[];
    await pumpBar(tester, path: '/photos/2024', events: events);

    await tester.tap(find.byKey(const ValueKey('breadcrumb_home')));
    await tester.pump();

    expect(events, ['home']);
    expect(find.byTooltip('Go to the top folder'), findsOneWidget);
  });
}

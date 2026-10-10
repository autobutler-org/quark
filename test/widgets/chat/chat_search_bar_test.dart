import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/chat/chat_search_bar.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart';

/// The chat search bar (#2429) says what it searched, the messages loaded on
/// this device, and offers older ones, on narrow and wide viewports alike.
void main() {
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> pumpBar(
    WidgetTester tester,
    Size size, {
    int? matchCount,
    bool hasOlder = false,
    bool isLoadingOlder = false,
    ValueChanged<String>? onChanged,
    VoidCallback? onLoadOlder,
    VoidCallback? onClose,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: ChatSearchBar(
              matchCount: matchCount,
              hasOlder: hasOlder,
              isLoadingOlder: isLoadingOlder,
              onChanged: onChanged ?? (_) {},
              onLoadOlder: onLoadOlder ?? () {},
              onClose: onClose ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  String status(WidgetTester tester) =>
      tester.widget<Text>(key('chat_search_status')).data!;

  for (final size in const [narrowViewport, wideViewport]) {
    testWidgets('says where it searches before a query at $size', (
      tester,
    ) async {
      await pumpBar(tester, size);

      expect(status(tester), ChatSearchBar.scopeText);
      expect(status(tester), contains('on this device'));
      expect(status(tester), contains('The Quark never sees'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('counts the matches in what is loaded at $size', (
      tester,
    ) async {
      for (final (count, text) in const [
        (0, 'No matches in the messages loaded on this device.'),
        (1, '1 match in the messages loaded on this device.'),
        (12, '12 matches in the messages loaded on this device.'),
      ]) {
        await pumpBar(tester, size, matchCount: count);
        expect(status(tester), text);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers older messages only while there are some at $size', (
      tester,
    ) async {
      var loads = 0;
      await pumpBar(tester, size, matchCount: 0);
      expect(key('chat_search_load_older'), findsNothing);

      await pumpBar(
        tester,
        size,
        matchCount: 0,
        hasOlder: true,
        onLoadOlder: () => loads++,
      );
      expect(find.text('Load older messages'), findsOneWidget);
      await tester.tap(key('chat_search_load_older'));
      await tester.pump();
      expect(loads, 1);

      await pumpBar(
        tester,
        size,
        matchCount: 0,
        hasOlder: true,
        isLoadingOlder: true,
        onLoadOlder: () => loads++,
      );
      expect(find.byType(QuarkLoader), findsOneWidget);
      await tester.tap(key('chat_search_load_older'), warnIfMissed: false);
      await tester.pump();
      expect(loads, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('typing and closing call out at $size', (tester) async {
      final typed = <String>[];
      var closes = 0;
      await pumpBar(
        tester,
        size,
        onChanged: typed.add,
        onClose: () => closes++,
      );

      await tester.enterText(key('chat_search_field'), 'lunch');
      await tester.pump();
      expect(typed, ['lunch']);

      expect(find.byTooltip('Close search'), findsOneWidget);
      await tester.tap(key('chat_search_close'));
      await tester.pump();
      expect(closes, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every control is a labeled 48dp target at $size', (
      tester,
    ) async {
      await pumpBar(tester, size, matchCount: 3, hasOlder: true);
      await expectTapTargetGuidelines(tester);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The one way an item's menu opens (#2267): at the pointer, running the
/// chosen entry only after the menu has closed.
void main() {
  Future<void> openAt(
    WidgetTester tester,
    List<QuarkMenuEntry> entries, {
    Size size = wideViewport,
    Brightness brightness = Brightness.dark,
    Offset position = const Offset(100, 100),
  }) async {
    await pumpAt(
      tester,
      Builder(
        builder: (context) => TextButton(
          key: const ValueKey('open'),
          onPressed: () =>
              showQuarkMenu(context, position: position, entries: entries),
          child: const Text('open'),
        ),
      ),
      size: size,
      brightness: brightness,
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    // Not pumpAndSettle: a busy row's loader never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testBothViewports('lists every row and runs the one picked, after closing', (
    tester,
    size,
  ) async {
    final events = <String>[];
    await openAt(tester, size: size, [
      QuarkMenuEntry(
        key: const ValueKey('rename'),
        label: 'Rename',
        icon: QuarkIcons.edit_outlined,
        onSelected: () => events.add('rename'),
      ),
      const QuarkMenuEntry.divider(),
      QuarkMenuEntry(
        key: const ValueKey('delete'),
        label: 'Delete',
        destructive: true,
        onSelected: () {
          // The menu's route is gone once the action runs, so a dialog it
          // opens lands over the page.
          final page = tester.element(find.byKey(const ValueKey('open')));
          events.add('delete:${ModalRoute.of(page)!.isCurrent}');
        },
      ),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete')));
    await tester.pumpAndSettle();

    expect(events, ['delete:true']);
    expect(find.text('Rename'), findsNothing);
  });

  testWidgets('opens where it is asked to', (tester) async {
    await openAt(tester, position: const Offset(300, 200), [
      QuarkMenuEntry(key: const ValueKey('a'), label: 'A', onSelected: () {}),
    ]);

    final row = tester.getRect(find.byKey(const ValueKey('a')));
    expect(row.left, closeTo(300, 16));
    expect(row.top, greaterThanOrEqualTo(200 - 16));
  });

  testWidgets('dismissing runs nothing', (tester) async {
    final events = <String>[];
    await openAt(tester, [
      QuarkMenuEntry(label: 'A', onSelected: () => events.add('a')),
    ]);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('A'), findsNothing);
    expect(events, isEmpty);
  });

  testWidgets('a row without an action is disabled', (tester) async {
    await openAt(tester, [
      const QuarkMenuEntry(
        key: ValueKey('off'),
        label: 'Off',
        onSelected: null,
      ),
    ]);

    final item = tester.widget<PopupMenuItem<int>>(
      find.byKey(const ValueKey('off')),
    );
    expect(item.enabled, isFalse);
  });

  testWidgets('a busy row shows a loader instead of its icon', (tester) async {
    await openAt(tester, [
      const QuarkMenuEntry(
        label: 'Extracting...',
        icon: QuarkIcons.edit_outlined,
        busy: true,
        onSelected: null,
      ),
    ]);

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byIcon(QuarkIcons.edit_outlined), findsNothing);
  });

  testWidgets('nothing opens without a row', (tester) async {
    await openAt(tester, const [QuarkMenuEntry.divider()]);

    expect(find.byType(PopupMenuDivider), findsNothing);
  });

  testBothViewports('survives a long label', (tester, size) async {
    await openAt(tester, size: size, [
      QuarkMenuEntry(label: 'Vacation ' * 40, onSelected: () {}),
    ]);

    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: a destructive row is in the error token', (
      tester,
    ) async {
      await openAt(brightness: brightness, tester, [
        QuarkMenuEntry(
          label: 'Delete',
          icon: QuarkIcons.delete_outline,
          destructive: true,
          onSelected: () {},
        ),
      ]);

      expect(
        tester.widget<Text>(find.text('Delete')).style?.color,
        tokens.error,
      );
      expect(
        tester.widget<Icon>(find.byIcon(QuarkIcons.delete_outline)).color,
        tokens.error,
      );
    });
  }
}

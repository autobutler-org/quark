import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_grid_sort_header.dart';
import 'package:quark/widgets/file_browser/file_browser_view/file_sort_header.dart';

import '../../../support/tap_target_guidelines.dart';
import '../../../support/text_scale.dart'
    show expectNoClippedText, testLargeText;

/// #2603, #2605: every column label is a 48dp button that says which way the
/// listing is sorted.
void main() {
  Future<List<SortColumn>> pump(
    WidgetTester tester,
    Size size, {
    required bool grid,
  }) async {
    setViewport(tester, size);
    final taps = <SortColumn>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: grid
                  ? FileGridSortHeader(
                      sortColumn: SortColumn.name,
                      sortDirection: SortDirection.asc,
                      onToggleSort: taps.add,
                    )
                  : FileSortHeader(
                      sortColumn: SortColumn.name,
                      sortDirection: SortDirection.asc,
                      onToggleSort: taps.add,
                      showFileSizeAndMenu: true,
                    ),
            ),
          ),
        ),
      ),
    );
    return taps;
  }

  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';
    for (final grid in [false, true]) {
      final view = grid ? 'grid' : 'list';
      testWidgets('$view header cells are labeled 48dp buttons ($label)', (
        tester,
      ) async {
        final taps = await pump(tester, size, grid: grid);
        final handle = tester.ensureSemantics();

        final name = tester.getSemantics(
          find.byKey(const ValueKey('file_sort_header_name')),
        );
        expect(name.flagsCollection.isButton, isTrue);
        expect(name.flagsCollection.isSelected, Tristate.isTrue);
        expect(name.label, 'Name');
        expect(name.value, 'Sorted ascending');

        final device = tester.getSemantics(
          find.byKey(const ValueKey('file_sort_header_device')),
        );
        expect(device.flagsCollection.isButton, isTrue);
        expect(device.flagsCollection.isSelected, Tristate.isFalse);
        expect(device.value, isEmpty);
        handle.dispose();

        await tester.tap(find.byKey(const ValueKey('file_sort_header_device')));
        expect(taps, [SortColumn.device]);

        await expectTapTargetGuidelines(tester);
      });
    }
  }

  // #2606: the column labels in the Trash listing (and Files) grow past the
  // header's height instead of being cut off.
  for (final grid in [false, true]) {
    final view = grid ? 'grid' : 'list';
    testLargeText('$view header cells fit their labels', (tester, size) async {
      await pump(tester, size, grid: grid);

      expect(tester.takeException(), isNull);
      expectNoClippedText(tester);
      await expectTapTargetGuidelines(tester);
    });
  }
}

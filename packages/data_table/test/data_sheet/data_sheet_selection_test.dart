import 'package:data_table/src/data_sheet/cell_range.dart';
import 'package:data_table/src/data_sheet/data_sheet_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DataSheetSelectionModel', () {
    late DataSheetSelectionModel selection;

    setUp(() {
      selection = DataSheetSelectionModel();
    });

    tearDown(() {
      selection.dispose();
    });

    test('initial state has no active cell or highlight', () {
      expect(selection.hasActiveCell, false);
      expect(selection.hasHighlight, false);
      expect(selection.activeRow, -1);
      expect(selection.activeCol, -1);
      expect(selection.highlightedRow, -1);
      expect(selection.highlightedCol, -1);
    });

    group('setActive', () {
      test('marks cell as active', () {
        selection.setActive(2, 3);
        expect(selection.activeRow, 2);
        expect(selection.activeCol, 3);
        expect(selection.hasActiveCell, true);
      });

      test('clears any existing highlight', () {
        selection.setHighlighted(1, 1);
        selection.setActive(2, 3);
        expect(selection.hasHighlight, false);
        expect(selection.highlightedRow, -1);
      });

      test('notifies listeners', () {
        var notified = false;
        selection.addListener(() => notified = true);
        selection.setActive(0, 0);
        expect(notified, true);
      });
    });

    group('setHighlighted', () {
      test('marks cell as highlighted', () {
        selection.setHighlighted(1, 2);
        expect(selection.highlightedRow, 1);
        expect(selection.highlightedCol, 2);
        expect(selection.hasHighlight, true);
      });

      test('does not clear an active cell', () {
        selection.setActive(0, 0);
        selection.setHighlighted(1, 1);
        expect(selection.hasActiveCell, true);
        expect(selection.activeRow, 0);
      });

      test('notifies listeners', () {
        var notified = false;
        selection.addListener(() => notified = true);
        selection.setHighlighted(0, 0);
        expect(notified, true);
      });
    });

    group('goTo', () {
      test('sets highlight and clears active cell', () {
        selection.setActive(1, 1);
        selection.goTo(3, 4);
        expect(selection.highlightedRow, 3);
        expect(selection.highlightedCol, 4);
        expect(selection.hasActiveCell, false);
        expect(selection.activeRow, -1);
      });

      test('notifies listeners', () {
        var notified = false;
        selection.addListener(() => notified = true);
        selection.goTo(2, 2);
        expect(notified, true);
      });
    });

    group('clear', () {
      test('clears both active cell and highlight', () {
        selection.setActive(1, 1);
        selection.setHighlighted(2, 2);
        selection.clear();
        expect(selection.hasActiveCell, false);
        expect(selection.hasHighlight, false);
      });

      test('notifies listeners', () {
        var notified = false;
        selection.addListener(() => notified = true);
        selection.clear();
        expect(notified, true);
      });
    });

    group('contextRow / contextCol', () {
      test('returns highlighted row/col when highlighted', () {
        selection.setActive(0, 0);
        selection.setHighlighted(2, 3);
        expect(selection.contextRow, 2);
        expect(selection.contextCol, 3);
      });

      test('falls back to active row/col when no highlight', () {
        selection.setActive(1, 2);
        expect(selection.contextRow, 1);
        expect(selection.contextCol, 2);
      });
    });
  });

  group('range selection', () {
    late DataSheetSelectionModel selection;

    setUp(() => selection = DataSheetSelectionModel());
    tearDown(() => selection.dispose());

    test('no highlight means no range', () {
      expect(selection.range, isNull);
      expect(selection.hasRange, false);
    });

    test('a highlighted cell is a one-cell range', () {
      selection.setHighlighted(1, 1);
      expect(selection.range, CellRange.fromCorners(1, 1, 1, 1));
      expect(selection.hasRange, false);
      expect(selection.extentRow, 1);
      expect(selection.extentCol, 1);
    });

    test('extendTo keeps the active cell and moves the far corner', () {
      selection.setHighlighted(1, 1);
      selection.extendTo(8, 3);
      expect(selection.highlightedRow, 1);
      expect(selection.highlightedCol, 1);
      expect(selection.extentRow, 8);
      expect(selection.extentCol, 3);
      expect(selection.hasRange, true);
      expect(selection.range!.label, 'B2:D9');
    });

    test('extendTo up and left normalizes the range', () {
      selection.setHighlighted(4, 4);
      selection.extendTo(2, 1);
      expect(selection.range,
          const CellRange(top: 2, left: 1, bottom: 4, right: 4));
    });

    test('extendTo with no highlight starts at the target', () {
      selection.extendTo(2, 2);
      expect(selection.highlightedRow, 2);
      expect(selection.highlightedCol, 2);
      expect(selection.hasRange, false);
    });

    test('extendTo commits nothing while a cell is being edited', () {
      selection.setActive(1, 1);
      selection.extendTo(3, 3);
      expect(selection.hasActiveCell, false);
      expect(selection.highlightedRow, 1);
      expect(selection.range!.label, 'B2:D4');
    });

    test('setHighlighted collapses the range', () {
      selection.setHighlighted(1, 1);
      selection.extendTo(3, 3);
      selection.setHighlighted(0, 0);
      expect(selection.hasRange, false);
      expect(selection.range!.label, 'A1');
    });

    test('goTo, setActive and clear collapse the range', () {
      selection.setHighlighted(1, 1);
      selection.extendTo(3, 3);
      selection.goTo(5, 5);
      expect(selection.hasRange, false);

      selection.extendTo(6, 6);
      selection.setActive(0, 0);
      expect(selection.hasRange, false);
      expect(selection.range, isNull);

      selection.setHighlighted(1, 1);
      selection.extendTo(2, 2);
      selection.clear();
      expect(selection.range, isNull);
      expect(selection.extentRow, -1);
    });

    test('selectRange sets the anchor and far corner', () {
      selection.setActive(0, 0);
      selection.selectRange(2, 0, 2, 4);
      expect(selection.hasActiveCell, false);
      expect(selection.highlightedRow, 2);
      expect(selection.highlightedCol, 0);
      expect(selection.range!.label, 'A3:E3');
    });

    test('isInRange covers every cell of the rectangle', () {
      selection.setHighlighted(1, 1);
      selection.extendTo(2, 3);
      expect(selection.isInRange(1, 1), true);
      expect(selection.isInRange(2, 3), true);
      expect(selection.isInRange(0, 1), false);
      expect(selection.isInRange(1, 4), false);
    });

    test('extendTo notifies listeners', () {
      selection.setHighlighted(0, 0);
      var notified = false;
      selection.addListener(() => notified = true);
      selection.extendTo(1, 1);
      expect(notified, true);
    });
  });

  group('CellRange', () {
    test('label of a single cell has no colon', () {
      expect(CellRange.fromCorners(0, 0, 0, 0).label, 'A1');
    });

    test('label spans multi-letter columns', () {
      expect(CellRange.fromCorners(0, 26, 99, 27).label, 'AA1:AB100');
    });

    test('row and column counts', () {
      final r = CellRange.fromCorners(1, 1, 8, 3);
      expect(r.rowCount, 8);
      expect(r.colCount, 3);
      expect(r.isSingleCell, false);
      expect(r.containsRow(8), true);
      expect(r.containsCol(4), false);
    });
  });
}

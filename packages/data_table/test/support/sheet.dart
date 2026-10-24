/// Shared setup for the data_table suites: tables built from cell values, the
/// test viewport, and a finder for a rendered cell.
library;

import 'package:data_table/src/data_sheet/data_sheet_controller.dart';
import 'package:data_table/src/models/data_cell.dart';
import 'package:data_table/src/models/data_row.dart';
import 'package:data_table/src/models/data_table.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone viewport every widget test runs at.
const narrow = Size(360, 640);

/// The desktop viewport every widget test runs at.
const wide = Size(1280, 800);

/// A table holding [values], one [DataRow] per inner list.
DataTable tableOf(List<List<String>> values) => DataTable([
  for (final row in values) DataRow([for (final value in row) DataCell(value)]),
]);

/// A [rows] by [cols] table whose cell at (r, c) reads `'r,c'`.
DataTable gridTable(int rows, int cols) =>
    tableOf(List.generate(rows, (r) => List.generate(cols, (c) => '$r,$c')));

/// A controller over [values]. The caller disposes it.
DataSheetController sheetOf(List<List<String>> values) =>
    DataSheetController.fromTable(tableOf(values));

/// Sizes the test view to [size] at a pixel ratio of 1, restored at teardown.
void setSheetSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The rendered cell at row [r], column [c].
Finder cellAt(int r, int c) => find.byKey(ValueKey('r${r}c$c'));

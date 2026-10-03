import 'package:data_table/data_sheet.dart';
import 'package:flutter/material.dart' hide DataCell, DataRow, DataTable;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formulaReferences', () {
    test('finds cells and ranges where they sit in the text', () {
      const formula = r'=SUM(b2:$D$9) + A1';
      final refs = formulaReferences(formula);
      expect(refs.map((r) => r.label), ['B2:D9', 'A1']);
      expect(
        refs.map((r) => formula.substring(r.source.start, r.source.end)),
        [r'b2:$D$9', 'A1'],
      );
      expect(refs.first.cells, CellRange.tryParse('B2:D9'));
    });

    test('colors references in order, and the same reference alike', () {
      final refs = formulaReferences('=A1+B2+A1');
      expect(refs[0].color, kFormulaReferencePalette[0]);
      expect(refs[1].color, kFormulaReferencePalette[1]);
      expect(refs[2].color, refs[0].color);
    });

    test('colors what it can of a formula still being typed', () {
      expect(formulaReferences('=SUM(A1, B2').map((r) => r.label), [
        'A1',
        'B2',
      ]);
      expect(formulaReferences('=A1 + "unfinished').map((r) => r.label), [
        'A1',
      ]);
    });

    test('nothing outside a formula', () {
      expect(formulaReferences('A1'), isEmpty);
      expect(formulaReferences(''), isEmpty);
      expect(formulaReferences('='), isEmpty);
    });
  });

  group('formulaReferenceCellColors', () {
    test('maps each referenced cell inside the sheet to its color', () {
      final colors = formulaReferenceCellColors(
        '=A1+SUM(B1:C2)+Z99',
        rowCount: 3,
        colCount: 3,
      );
      expect(colors.keys.toSet(), {(0, 0), (0, 1), (0, 2), (1, 1), (1, 2)});
      expect(colors[(0, 0)], kFormulaReferencePalette[0]);
      expect(colors[(1, 2)], kFormulaReferencePalette[1]);
    });
  });

  group('FormulaTextEditingController', () {
    testWidgets('colors each reference in its text', (tester) async {
      final controller = FormulaTextEditingController(text: '=A1+SUM(B2:C3)');
      addTearDown(controller.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      final span = controller.buildTextSpan(
        context: context,
        withComposing: false,
      );
      final colored = <String, Color?>{};
      span.visitChildren((child) {
        if (child is TextSpan && child.text != null) {
          colored[child.text!] = child.style?.color;
        }
        return true;
      });
      expect(colored['A1'], kFormulaReferencePalette[0]);
      expect(colored['B2:C3'], kFormulaReferencePalette[1]);
      expect(colored['+SUM('], isNull);
    });
  });
}

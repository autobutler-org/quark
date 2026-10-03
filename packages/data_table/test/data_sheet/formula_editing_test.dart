import 'package:data_table/data_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// [text] with the caret where `|` is.
TextEditingValue at(String text) {
  final caret = text.indexOf('|');
  return TextEditingValue(
    text: text.replaceFirst('|', ''),
    selection: TextSelection.collapsed(offset: caret),
  );
}

/// [value]'s text with `|` at its caret.
String show(TextEditingValue value) {
  final caret = value.selection.baseOffset;
  return '${value.text.substring(0, caret)}|${value.text.substring(caret)}';
}

void main() {
  group('functionQueryAt', () {
    test('finds the name being typed after =, an operator, ( or ,', () {
      expect(functionQueryAt(at('=SU|'))?.prefix, 'SU');
      expect(functionQueryAt(at('=1+su|'))?.prefix, 'su');
      expect(functionQueryAt(at('=SUM(A1, AV|'))?.prefix, 'AV');
      expect(functionQueryAt(at('=IF(CO|'))?.prefix, 'CO');
      expect(functionQueryAt(at('= MA|'))?.prefix, 'MA');
    });

    test('spans the whole word around the caret start', () {
      final query = functionQueryAt(at('=1+COU|'))!;
      expect((query.start, query.end), (3, 6));
    });

    test('is null outside a formula, a name, or at a reference', () {
      expect(functionQueryAt(at('SU|')), isNull);
      expect(functionQueryAt(at('=|')), isNull);
      expect(functionQueryAt(at('=A1|')), isNull);
      expect(functionQueryAt(at(r'=$A|')), isNull);
      expect(functionQueryAt(at('=SUM(|')), isNull);
      expect(functionQueryAt(at('=SU|M')), isNull);
      expect(functionQueryAt(at('="SU|')), isNull);
      expect(functionQueryAt(at('=3SU|')), isNull);
    });

    test('is null with a selection rather than a caret', () {
      expect(
        functionQueryAt(
          const TextEditingValue(
            text: '=SU',
            selection: TextSelection(baseOffset: 1, extentOffset: 3),
          ),
        ),
        isNull,
      );
    });
  });

  group('acceptFunction', () {
    test('replaces the typed name and opens its parenthesis', () {
      final value = at('=1+su|');
      final accepted = acceptFunction(value, functionQueryAt(value)!, 'SUM');
      expect(show(accepted), '=1+SUM(|');
    });

    test('keeps a parenthesis already there', () {
      final value = at('=AV|(A1)').copyWith();
      // A caret mid-word is not a query; build one by hand.
      const query = FunctionQuery(start: 1, end: 3, prefix: 'AV');
      expect(show(acceptFunction(value, query, 'AVERAGE')), '=AVERAGE(|A1)');
    });
  });

  group('acceptsReferenceAt', () {
    test('after =, an operator, an open parenthesis, a comma or a colon', () {
      for (final text in [
        '=|',
        '=1+|',
        '=SUM(|',
        '=SUM(A1, |',
        '=A1:|',
        '=2*|',
        '=A1>=|',
        '=(|)',
      ]) {
        final v = at(text);
        expect(
          acceptsReferenceAt(v.text, v.selection.baseOffset),
          isTrue,
          reason: text,
        );
      }
    });

    test('not after a value, inside a string, or outside a formula', () {
      for (final text in [
        '|',
        'A|',
        '=A1|',
        '=SUM(A1)|',
        '=3|',
        '="a|',
        '=SUM|',
        '=+|B2',
      ]) {
        final v = at(text);
        expect(
          acceptsReferenceAt(v.text, v.selection.baseOffset),
          isFalse,
          reason: text,
        );
      }
    });
  });

  group('pickReference', () {
    test('inserts at the caret and reports where', () {
      final pick = pickReference(at('=SUM(|)'), 'B2')!;
      expect(show(pick.value), '=SUM(B2|)');
      expect(pick.inserted, const TextRange(start: 5, end: 7));
    });

    test('replaces a selection that accepts a reference', () {
      const value = TextEditingValue(
        text: '=1+xx',
        selection: TextSelection(baseOffset: 3, extentOffset: 5),
      );
      expect(show(pickReference(value, 'C3')!.value), '=1+C3|');
    });

    test('replaces the pending pick, so a drag grows it into a range', () {
      final first = pickReference(at('=SUM(|)'), 'B2')!;
      final grown =
          pickReference(first.value, 'B2:D9', pending: first.inserted)!;
      expect(show(grown.value), '=SUM(B2:D9|)');
      expect(grown.inserted, const TextRange(start: 5, end: 10));
      final moved = pickReference(grown.value, 'C4', pending: grown.inserted)!;
      expect(show(moved.value), '=SUM(C4|)');
    });

    test('a pending pick the user has typed past is not replaced', () {
      final first = pickReference(at('=|'), 'B2')!;
      final typed = at('=B2+|');
      final next = pickReference(typed, 'C3', pending: first.inserted)!;
      expect(show(next.value), '=B2+C3|');
    });

    test('is null where no reference fits', () {
      expect(pickReference(at('=A1|'), 'B2'), isNull);
      expect(pickReference(at('hello|'), 'B2'), isNull);
    });
  });

  group('CellRange.tryParse', () {
    test('reads cells and ranges, in any case and with \$', () {
      expect(
        CellRange.tryParse('B2'),
        const CellRange(top: 1, left: 1, bottom: 1, right: 1),
      );
      expect(CellRange.tryParse(r'$b$2:d9')?.label, 'B2:D9');
      expect(CellRange.tryParse('D9:B2')?.label, 'B2:D9');
      expect(CellRange.tryParse('AA10')?.left, 26);
    });

    test('is null for anything else', () {
      for (final text in ['', 'B', '2', 'B0', 'B2:', 'SUM', 'B2:C']) {
        expect(CellRange.tryParse(text), isNull, reason: text);
      }
    });
  });
}

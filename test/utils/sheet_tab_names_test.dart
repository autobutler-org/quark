import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/sheet_tab_names.dart';

void main() {
  group('nextSheetName', () {
    test('starts at Sheet 1', () {
      expect(nextSheetName(const []), 'Sheet 1');
    });

    test('goes one past the highest, leaving gaps unused', () {
      expect(nextSheetName(const ['Sheet 1', 'Sheet 3']), 'Sheet 4');
    });

    test('counts names in another case and ignores other names', () {
      expect(nextSheetName(const ['sheet 2', 'Budget', 'Sheet 2b']), 'Sheet 3');
    });
  });

  group('copySheetName', () {
    test('appends (copy)', () {
      expect(copySheetName('Budget', const ['Budget']), 'Budget (copy)');
    });

    test('numbers further copies', () {
      expect(
        copySheetName('Budget', const ['Budget', 'budget (COPY)']),
        'Budget (copy 2)',
      );
      expect(
        copySheetName('Budget', const [
          'Budget',
          'Budget (copy)',
          'Budget (copy 2)',
        ]),
        'Budget (copy 3)',
      );
    });
  });

  group('sheetNameError', () {
    const names = ['Sheet 1', 'Budget'];

    test('refuses a blank name', () {
      expect(sheetNameError('   ', names, 0), Errors.nameBlank);
    });

    test('refuses another tab name, ignoring case', () {
      expect(sheetNameError('budget', names, 0), Errors.sheetNameTaken);
    });

    test('lets a tab keep or recase its own name', () {
      expect(sheetNameError('BUDGET', names, 1), isNull);
    });

    test('accepts a free name', () {
      expect(sheetNameError('Totals', names, 0), isNull);
    });
  });
}

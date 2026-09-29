import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/vault_import_summary.dart';

/// #2543: a Proton Pass export carries notes, aliases and cards the vault has
/// no place for. They are counted apart from duplicates and errors, so the
/// summary doesn't call them either.
void main() {
  test('reports only what was imported when nothing else happened', () {
    expect(
      vaultImportSummary({'imported': 12, 'skipped': 0}),
      'Imported 12 entries',
    );
  });

  test('names each count that happened', () {
    expect(
      vaultImportSummary({
        'imported': 2,
        'skipped': 1,
        'ignored': 3,
        'errors': ['Row 7: login has no username or password'],
      }),
      'Imported 2 entries, 1 skipped (duplicates), 3 non-login items left out, 1 errors',
    );
  });

  test('reads a response from a Quark that predates the ignored count', () {
    expect(
      vaultImportSummary({'imported': 4, 'skipped': 2}),
      'Imported 4 entries, 2 skipped (duplicates)',
    );
  });
}

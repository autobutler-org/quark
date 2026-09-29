/// The one-line result of a vault import, shown in a snack bar (#2543).
///
/// `skipped` counts entries already in the vault, `ignored` counts items the
/// vault has no place for (Proton Pass notes, aliases and cards), and each of
/// `errors` is a row the import could not take. A count of zero says nothing,
/// so only the ones that happened are mentioned.
String vaultImportSummary(Map<String, dynamic> response) {
  final imported = response['imported'] as int? ?? 0;
  final skipped = response['skipped'] as int? ?? 0;
  final ignored = response['ignored'] as int? ?? 0;
  final errors = (response['errors'] as List?)?.length ?? 0;
  return [
    'Imported $imported entries',
    if (skipped > 0) '$skipped skipped (duplicates)',
    if (ignored > 0) '$ignored non-login items left out',
    if (errors > 0) '$errors errors',
  ].join(', ');
}

import 'package:quark/utils/error_text.dart';

/// Naming rules for the tabs of a spreadsheet (#1745). Names compare
/// case-insensitively, so "budget" and "Budget" cannot both be tabs.

bool _taken(String name, Iterable<String> names) {
  final lower = name.toLowerCase();
  return names.any((n) => n.toLowerCase() == lower);
}

final _sheetNumber = RegExp(r'^sheet (\d+)$', caseSensitive: false);

/// `Sheet N` for a new tab, N one past the highest `Sheet N` already there,
/// so a deleted number is never reused. `Sheet 1` when there is none.
String nextSheetName(List<String> names) {
  var max = 0;
  for (final name in names) {
    final n = int.tryParse(_sheetNumber.firstMatch(name)?.group(1) ?? '');
    if (n != null && n > max) max = n;
  }
  return 'Sheet ${max + 1}';
}

/// The name for a duplicate of [name]: `<name> (copy)`, then
/// `<name> (copy 2)`, `<name> (copy 3)` and on until one is free.
String copySheetName(String name, List<String> names) {
  if (!_taken('$name (copy)', names)) return '$name (copy)';
  for (var n = 2; ; n++) {
    final candidate = '$name (copy $n)';
    if (!_taken(candidate, names)) return candidate;
  }
}

/// Why [name] cannot be the name of the tab at [index] among [names], or
/// null when it can. A tab keeping its own name, in any case, is allowed.
String? sheetNameError(String name, List<String> names, int index) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return Errors.nameBlank;
  final others = [
    for (var i = 0; i < names.length; i++)
      if (i != index) names[i],
  ];
  return _taken(trimmed, others) ? Errors.sheetNameTaken : null;
}

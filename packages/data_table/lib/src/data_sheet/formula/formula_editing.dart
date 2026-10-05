import 'package:flutter/services.dart'
    show TextEditingValue, TextRange, TextSelection;

/// The function name being typed in a formula: the word from [start] to [end] in the text, which reads [prefix].
///
/// [functionQueryAt] finds it, and [acceptFunction] replaces it with a chosen name. This file holds the text logic
/// behind function autocomplete and reference picking, kept apart from widgets so it can be tested on its own.
class FunctionQuery {
  /// Where the word starts.
  final int start;

  /// Where the word ends, which is the caret.
  final int end;

  /// The word as typed.
  final String prefix;

  const FunctionQuery({
    required this.start,
    required this.end,
    required this.prefix,
  });
}

/// The function name being typed at [value]'s caret, or null when the caret
/// does not end one.
///
/// A name is a word that starts with a letter and ends at the caret, in a
/// formula (text starting with `=`), where a value may start: right after
/// the `=`, an operator, `(` or `,`. A cell reference (`A1`, `$B`), a word
/// inside a string, and a word the caret sits in the middle of are not names.
FunctionQuery? functionQueryAt(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection;
  if (!text.startsWith('=') || !selection.isValid || !selection.isCollapsed) {
    return null;
  }
  final caret = selection.baseOffset;
  if (caret < text.length && _isWordChar(text.codeUnitAt(caret))) return null;
  var start = caret;
  while (start > 1 && _isWordChar(text.codeUnitAt(start - 1))) {
    start--;
  }
  if (start == caret || !_isLetter(text.codeUnitAt(start))) return null;
  final word = text.substring(start, caret);
  if (_cellLike.hasMatch(word)) return null;
  if (!_valueMayStartAt(text, start)) return null;
  return FunctionQuery(start: start, end: caret, prefix: word);
}

/// [value] with [query]'s word replaced by [name] and an opening parenthesis,
/// the caret after it. A parenthesis already following the word is reused.
TextEditingValue acceptFunction(
  TextEditingValue value,
  FunctionQuery query,
  String name,
) {
  final text = value.text;
  final after = text.substring(query.end);
  final opened = after.startsWith('(') ? name : '$name(';
  final caret = query.start + opened.length + (after.startsWith('(') ? 1 : 0);
  return TextEditingValue(
    text: '${text.substring(0, query.start)}$opened$after',
    selection: TextSelection.collapsed(offset: caret),
  );
}

/// Whether a cell reference typed at [caret] in [text] would read as one:
/// the text is a formula, the caret is not inside a string, the nearest
/// character before it is the `=`, an operator, `(`, `,` or `:`, and no word
/// follows it to run into.
bool acceptsReferenceAt(String text, int caret) {
  if (!text.startsWith('=') || caret < 1 || caret > text.length) return false;
  if (caret < text.length) {
    final next = text.codeUnitAt(caret);
    if (_isWordChar(next) || next == _quote) return false;
  }
  return _valueMayStartAt(text, caret, allowColon: true);
}

/// Inserts [reference] (`B2` or `B2:D9`) into [value] as a pick from the
/// grid, returning the new value and where the reference landed, or null
/// when no reference fits at the caret.
///
/// [pending] is where the previous pick landed. While the caret still sits at
/// its end and it still reads as a reference, the new pick replaces it, so
/// clicking another cell moves the reference and dragging grows it into a
/// range. Otherwise the reference goes at the caret, replacing any selection,
/// where [acceptsReferenceAt] allows. With no caret yet, the end of the text
/// stands in for it.
({TextEditingValue value, TextRange inserted})? pickReference(
  TextEditingValue value,
  String reference, {
  TextRange? pending,
}) {
  final text = value.text;
  // A caret the field has not placed yet is at the end.
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: text.length);
  final TextRange target;
  if (pending != null &&
      selection.isCollapsed &&
      pending.end == selection.baseOffset &&
      pending.end <= text.length &&
      _referenceLike.hasMatch(text.substring(pending.start, pending.end))) {
    target = pending;
  } else if (acceptsReferenceAt(
    text.replaceRange(selection.start, selection.end, ''),
    selection.start,
  )) {
    target = TextRange(start: selection.start, end: selection.end);
  } else {
    return null;
  }
  final end = target.start + reference.length;
  return (
    value: TextEditingValue(
      text: text.replaceRange(target.start, target.end, reference),
      selection: TextSelection.collapsed(offset: end),
    ),
    inserted: TextRange(start: target.start, end: end),
  );
}

const _quote = 0x22;

/// A word that is a cell reference, or the start of one with `$`.
final _cellLike = RegExp(r'^[A-Za-z]+[0-9]+$');

/// A whole cell or range reference.
final _referenceLike = RegExp(
  r'^\$?[A-Za-z]+\$?[0-9]+(:\$?[A-Za-z]+\$?[0-9]+)?$',
);

bool _isLetter(int c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122);

bool _isWordChar(int c) =>
    _isLetter(c) || (c >= 48 && c <= 57) || c == 0x5F || c == 0x24;

/// Whether a value may start at [index] in formula [text]: outside a string,
/// with only spaces between it and the `=`, an operator, `(` or `,` (or `:`
/// when [allowColon]) before it.
bool _valueMayStartAt(String text, int index, {bool allowColon = false}) {
  var quotes = 0;
  for (var i = 1; i < index; i++) {
    if (text.codeUnitAt(i) == _quote) quotes++;
  }
  if (quotes.isOdd) return false;
  var i = index - 1;
  while (i > 0 && text[i] == ' ') {
    i--;
  }
  if (i == 0) return true;
  final before = text[i];
  return '+-*/^%&(,<>='.contains(before) || allowColon && before == ':';
}

import '../model/rich_text.dart';
import '../model/text_paragraph.dart';
import '../model/text_run.dart';
import 'slide_match.dart';

// Pure functions behind `SlideDocumentController.replaceCurrent` and
// `replaceAll`: replacing matches in a text box's paragraphs or in a
// slide's notes, tested on their own.
//
// Matches are replaced from the last to the first, so the offsets of the
// ones before stay true as the text changes length. A match whose text is
// no longer where it was found — the document moved on since the search —
// is skipped, and so is one overlapping a match already replaced.

/// [paragraphs] with each of [matches] — all found in this text — replaced
/// by [replacement], and how many were.
///
/// The replacement takes the formatting of the run holding a match's first
/// character, whatever runs the match spans; `replaceText` splits the
/// runs at the match's edges and merges the result with same-styled
/// neighbors. A `\n` in [replacement] starts a new paragraph.
///
/// ```dart
/// replaceInParagraphs(
///   [TextParagraph([TextRun('big ', bold: true), TextRun('cat')])],
///   [match], // 'g c', from offset 2 to 5
///   'x',
/// ).paragraphs; // [TextParagraph([TextRun('bix', bold: true), TextRun('at')])]
/// ```
({List<TextParagraph> paragraphs, int count}) replaceInParagraphs(
  List<TextParagraph> paragraphs,
  Iterable<SlideMatch> matches,
  String replacement,
) {
  var result = paragraphs;
  var count = 0;
  int? floor;
  for (final match in _lastFirst(matches)) {
    if (match.paragraph >= result.length) continue;
    final paragraph = result[match.paragraph];
    if (!_stillThere(paragraph.plainText, match)) continue;
    final at = match.offsetIn([for (final p in result) p.plainText]);
    if (floor != null && at + match.text.length > floor) continue;
    result = replaceText(
      result,
      at,
      at + match.text.length,
      replacement,
      style: _runAt(paragraph.runs, match.start),
    );
    floor = at;
    count++;
  }
  return (paragraphs: result, count: count);
}

/// [notes] with each of [matches] — all found in these notes — replaced by
/// [replacement], and how many were.
({String notes, int count}) replaceInNotes(
  String notes,
  Iterable<SlideMatch> matches,
  String replacement,
) {
  var result = notes;
  var count = 0;
  int? floor;
  for (final match in _lastFirst(matches)) {
    final lines = result.split('\n');
    if (match.paragraph >= lines.length) continue;
    if (!_stillThere(lines[match.paragraph], match)) continue;
    final at = match.offsetIn(lines);
    if (floor != null && at + match.text.length > floor) continue;
    result = result.replaceRange(at, at + match.text.length, replacement);
    floor = at;
    count++;
  }
  return (notes: result, count: count);
}

List<SlideMatch> _lastFirst(Iterable<SlideMatch> matches) =>
    [...matches]..sort((a, b) => b.compareTo(a));

bool _stillThere(String line, SlideMatch match) =>
    match.end <= line.length &&
    match.end - match.start == match.text.length &&
    line.substring(match.start, match.end) == match.text;

/// The run holding the character at [offset] of a paragraph.
TextRun? _runAt(List<TextRun> runs, int offset) {
  var seen = 0;
  for (final run in runs) {
    seen += run.text.length;
    if (offset < seen) return run;
  }
  return runs.isEmpty ? null : runs.last;
}

import 'dart:math' as math;

import 'slide_element.dart';
import 'text_format.dart';
import 'text_paragraph.dart';
import 'text_run.dart';
import 'unset.dart';

// Pure functions over a text box's paragraphs and runs: the editing and
// formatting the slide editor does, kept out of widgets so each case can be
// tested on its own.
//
// Offsets count characters in the box's plain text, its paragraphs joined by
// `\n` (`TextBox.plainText`), so a selection made in an editor maps straight
// onto them. None of these functions change their input; each returns new
// paragraphs whose runs are normalized: no run is empty and no two
// neighbors share a style, except that a paragraph with no text may keep
// one empty run to remember the style typing there starts with. Unknown
// fields (`extra`) ride along on every run and paragraph they came in on.

/// Replaces the characters from [start] to [end] of [paragraphs] with
/// [inserted], whose `\n`s start new paragraphs, and returns the result.
///
/// Inserted characters take [style]'s formatting when given (its text is
/// ignored), or else the formatting of the character before [start] —
/// the one after it at the start of a paragraph — as typing does. A
/// paragraph split by a line break passes its alignment, spacing and list
/// style on to the new one; paragraphs joined by deleting a line break keep
/// the first one's.
///
/// ```dart
/// replaceText([TextParagraph([TextRun('Hi', bold: true)])], 2, 2, '!\nYo');
/// // [TextParagraph([TextRun('Hi!', bold: true)]),
/// //  TextParagraph([TextRun('Yo', bold: true)])]
/// ```
List<TextParagraph> replaceText(
  List<TextParagraph> paragraphs,
  int start,
  int end,
  String inserted, {
  TextRun? style,
}) {
  final source = paragraphs.isEmpty ? const [TextParagraph([])] : paragraphs;
  final length = _length(source);
  start = start.clamp(0, length);
  end = end.clamp(start, length);
  final (pi, oi) = _locate(source, start);
  final (pj, oj) = _locate(source, end);
  final first = source[pi];
  final template = (style ?? _styleAt(first, oi)).copyWith(text: '');
  final left = _slice(first.runs, 0, oi);
  final right = _slice(source[pj].runs, oj, source[pj].plainText.length);
  final lines = inserted.split('\n');
  TextParagraph paragraph(List<TextRun> runs) =>
      first.copyWith(runs: _normalize(runs, template));
  TextRun line(String text) => template.copyWith(text: text);
  final middle = [
    if (lines.length == 1)
      paragraph([...left, line(lines.single), ...right])
    else ...[
      paragraph([...left, line(lines.first)]),
      for (final text in lines.sublist(1, lines.length - 1))
        paragraph([line(text)]),
      paragraph([line(lines.last), ...right]),
    ],
  ];
  return List.unmodifiable([
    ...source.take(pi),
    ...middle,
    ...source.skip(pj + 1),
  ]);
}

/// Applies [format] to the text from [start] to [end] of [paragraphs], or
/// to all of it when they are left out.
///
/// Run fields restyle the selected characters, splitting runs at the
/// selection's edges; a collapsed selection restyles nothing unless it sits
/// in an empty paragraph, whose remembered typing style it sets. Paragraph
/// fields restyle every paragraph the selection touches, including the one
/// a collapsed selection sits in. Box fields are ignored here; see
/// [formatTextBox].
List<TextParagraph> formatParagraphs(
  List<TextParagraph> paragraphs,
  TextFormat format, {
  int? start,
  int? end,
}) {
  final source = paragraphs.isEmpty ? const [TextParagraph([])] : paragraphs;
  final length = _length(source);
  final from = (start ?? 0).clamp(0, length);
  final to = (end ?? length).clamp(from, length);
  var offset = 0;
  final result = <TextParagraph>[];
  for (final paragraph in source) {
    final ps = offset;
    final pe = ps + paragraph.plainText.length;
    offset = pe + 1;
    if (ps > to || pe < from) {
      result.add(paragraph);
      continue;
    }
    var next = paragraph;
    if (format.changesRuns) {
      final a = math.max(from, ps) - ps;
      final b = math.min(to, pe) - ps;
      if (pe == ps) {
        final empty = paragraph.runs.isEmpty
            ? const TextRun('')
            : paragraph.runs.first.copyWith(text: '');
        final styled = format.applyToRun(empty);
        next = next.copyWith(runs: _normalize(const [], styled));
      } else if (a < b) {
        next = next.copyWith(
          runs: _normalize([
            ..._slice(paragraph.runs, 0, a),
            for (final run in _slice(paragraph.runs, a, b))
              format.applyToRun(run),
            ..._slice(paragraph.runs, b, pe - ps),
          ], const TextRun('')),
        );
      }
    }
    if (format.changesParagraphs) next = format.applyToParagraph(next);
    result.add(next);
  }
  return List.unmodifiable(result);
}

/// [box] with [format] applied: its run and paragraph fields to the text
/// from [start] to [end] (all of it when left out) as [formatParagraphs]
/// does, and its box fields to the box.
TextBox formatTextBox(TextBox box, TextFormat format, {int? start, int? end}) {
  final styled = format.applyToBox(box);
  if (!format.changesRuns && !format.changesParagraphs) return styled;
  return styled.copyWith(
    paragraphs: formatParagraphs(
      box.paragraphs,
      format,
      start: start,
      end: end,
    ),
  );
}

/// What formatting the text from [start] to [end] of [paragraphs] shares —
/// all of it when they are left out — as a summary [TextFormat] (see its
/// doc). With [box], the box fields are filled in too.
///
/// Run fields come from the selected characters, or for a collapsed
/// selection from the style typing there would use: the character before
/// it, or an empty paragraph's remembered style. Paragraph fields come from
/// every paragraph the selection touches.
TextFormat textFormatOf(
  List<TextParagraph> paragraphs, {
  int? start,
  int? end,
  TextBox? box,
}) {
  final source = paragraphs.isEmpty ? const [TextParagraph([])] : paragraphs;
  final length = _length(source);
  final from = (start ?? 0).clamp(0, length);
  final to = (end ?? length).clamp(from, length);
  final runs = <TextRun>[];
  final touched = <TextParagraph>[];
  var offset = 0;
  for (final paragraph in source) {
    final ps = offset;
    final pe = ps + paragraph.plainText.length;
    offset = pe + 1;
    if (ps > to || pe < from) continue;
    touched.add(paragraph);
    final a = math.max(from, ps) - ps;
    final b = math.min(to, pe) - ps;
    if (a < b) runs.addAll(_slice(paragraph.runs, a, b));
  }
  if (runs.isEmpty) {
    final (pi, oi) = _locate(source, from);
    runs.add(_styleAt(source[pi], oi));
  }
  T? same<T>(T Function(TextRun) field) {
    final value = field(runs.first);
    return runs.every((r) => field(r) == value) ? value : null;
  }

  Object? sameNullable(Object? Function(TextRun) field) {
    final value = field(runs.first);
    return runs.every((r) => field(r) == value) ? value : unset;
  }

  T? shared<T>(T Function(TextParagraph) field) {
    final value = field(touched.first);
    return touched.every((p) => field(p) == value) ? value : null;
  }

  final spacing = touched.first.lineSpacing;
  return TextFormat(
    bold: same((r) => r.bold),
    italic: same((r) => r.italic),
    underline: same((r) => r.underline),
    strikethrough: same((r) => r.strikethrough),
    fontSize: sameNullable((r) => r.fontSize),
    fontFamily: sameNullable((r) => r.fontFamily),
    color: sameNullable((r) => r.color),
    alignment: shared((p) => p.alignment),
    lineSpacing:
        touched.every((p) => p.lineSpacing == spacing) ? spacing : unset,
    list: shared((p) => p.list),
    anchor: box?.anchor,
    autoFit: box?.autoFit,
  );
}

/// The list marker drawn before each paragraph, or `null` for one that is
/// not a list item: `•` for a bullet, and `1.`, `2.`, … for numbered
/// paragraphs, counting from the first of each unbroken run of them.
List<String?> listMarkers(List<TextParagraph> paragraphs) {
  final markers = <String?>[];
  var count = 0;
  for (final paragraph in paragraphs) {
    count = paragraph.list == TextListStyle.numbered ? count + 1 : 0;
    markers.add(switch (paragraph.list) {
      TextListStyle.none => null,
      TextListStyle.bullet => '•',
      TextListStyle.numbered => '$count.',
    });
  }
  return markers;
}

/// The style typing at the box offset [offset] of [paragraphs] takes, as a
/// run with no text: the run holding the character before it, the first
/// run at a paragraph's start, or the paragraph's remembered style when it
/// has no text.
TextRun typingStyleAt(List<TextParagraph> paragraphs, int offset) {
  if (paragraphs.isEmpty) return const TextRun('');
  final (pi, oi) = _locate(paragraphs, offset.clamp(0, _length(paragraphs)));
  return _styleAt(paragraphs[pi], oi).copyWith(text: '');
}

/// The style typing at [offset] in [paragraph] takes: the run holding the
/// character before it, the first run at the start, or the paragraph's
/// remembered style when it has no text.
TextRun _styleAt(TextParagraph paragraph, int offset) {
  if (paragraph.runs.isEmpty) return const TextRun('');
  var seen = 0;
  for (final run in paragraph.runs) {
    seen += run.text.length;
    if (offset <= seen && run.text.isNotEmpty) return run;
  }
  return paragraph.runs.last;
}

int _length(List<TextParagraph> paragraphs) =>
    paragraphs.fold(-1, (sum, p) => sum + p.plainText.length + 1);

/// The paragraph holding the box offset [offset], and the offset within it.
(int, int) _locate(List<TextParagraph> paragraphs, int offset) {
  for (var i = 0; i < paragraphs.length; i++) {
    final length = paragraphs[i].plainText.length;
    if (offset <= length) return (i, offset);
    offset -= length + 1;
  }
  return (paragraphs.length - 1, paragraphs.last.plainText.length);
}

/// The parts of [runs] between the paragraph offsets [start] and [end].
List<TextRun> _slice(List<TextRun> runs, int start, int end) {
  final result = <TextRun>[];
  var offset = 0;
  for (final run in runs) {
    final a = math.max(start, offset);
    final b = math.min(end, offset + run.text.length);
    if (a < b) {
      result
          .add(run.copyWith(text: run.text.substring(a - offset, b - offset)));
    }
    offset += run.text.length;
  }
  return result;
}

/// [runs] with empty runs dropped and same-styled neighbors merged. When no
/// text is left, [empty]'s style is kept as one empty run, unless it is the
/// plain default.
List<TextRun> _normalize(List<TextRun> runs, TextRun empty) {
  final result = <TextRun>[];
  for (final run in runs) {
    if (run.text.isEmpty) continue;
    if (result.isNotEmpty && result.last.hasStyleOf(run)) {
      result.last = result.last.copyWith(text: result.last.text + run.text);
    } else {
      result.add(run);
    }
  }
  if (result.isEmpty) {
    final remembered = empty.copyWith(text: '');
    if (remembered != const TextRun('')) result.add(remembered);
  }
  return List.unmodifiable(result);
}

import 'package:flutter/widgets.dart';

import '../model/text_paragraph.dart';
import 'slide_text_layout.dart';

/// Called when the user changes a paragraph field's text: the field
/// characters from [start] to [end] became [inserted], and [value] is what
/// the field asked to hold afterward.
typedef SlideParagraphEdit = void Function(
  int start,
  int end,
  String inserted,
  TextEditingValue value,
);

/// The [TextEditingController] of one paragraph in the in-place text
/// editor: it maps between the field's plain text and the paragraph's
/// styled runs.
///
/// It draws [paragraph]'s runs with [layout] in [buildTextSpan], so the
/// field shows rich text, and it does not change the runs itself: when the
/// user changes the text it works out which characters changed and reports
/// them to [onEdit], and the owner — `SlideTextEditingController` — edits
/// the runs and calls [sync] with the result. Selection and composing
/// changes pass straight through.
///
/// Every paragraph but the first starts with [lineBreak], a zero-width
/// character standing for the line break before it, so deleting it — a
/// backspace at the start of the paragraph, from a hardware keyboard or a
/// phone's — joins the paragraph to the one before, the way it does in a
/// single text field.
class SlideParagraphEditingController extends TextEditingController {
  /// Creates the controller of [paragraph].
  SlideParagraphEditingController({
    required TextParagraph paragraph,
    required this.leadingBreak,
    required this.layout,
    this.onEdit,
    this.onSelectionChanged,
  }) : _paragraph = paragraph {
    super.value = TextEditingValue(text: _fieldText);
  }

  /// The zero-width character a paragraph after the first starts with.
  static const lineBreak = '​';

  TextParagraph _paragraph;

  /// The paragraph shown, as of the last [sync].
  TextParagraph get paragraph => _paragraph;

  /// Whether the field starts with [lineBreak].
  bool leadingBreak;

  /// Styles the runs.
  SlideTextLayout layout;

  /// The shrink-to-fit scale the box is drawn at.
  double scale = 1;

  /// Hears about text changes; see the class doc.
  SlideParagraphEdit? onEdit;

  /// Hears about selection changes that leave the text alone.
  ValueChanged<TextSelection>? onSelectionChanged;

  /// How many field characters come before the paragraph's text: 1 with a
  /// [leadingBreak], else 0.
  int get lead => leadingBreak ? 1 : 0;

  String get _fieldText =>
      (leadingBreak ? lineBreak : '') + _paragraph.plainText;

  /// Shows [paragraph], with the field's selection and composing range set
  /// to [selection] and [composing], without reporting an edit.
  void sync(
    TextParagraph paragraph, {
    required bool leadingBreak,
    required TextSelection selection,
    TextRange composing = TextRange.empty,
  }) {
    _paragraph = paragraph;
    this.leadingBreak = leadingBreak;
    final text = _fieldText;
    super.value = TextEditingValue(
      text: text,
      selection: _clamp(selection, text.length),
      composing: composing.isValid && composing.end <= text.length
          ? composing
          : TextRange.empty,
    );
  }

  static TextSelection _clamp(TextSelection selection, int length) =>
      selection.copyWith(
        baseOffset: selection.baseOffset.clamp(0, length),
        extentOffset: selection.extentOffset.clamp(0, length),
      );

  @override
  set value(TextEditingValue newValue) {
    final old = text;
    final next = newValue.text;
    if (next == old) {
      // An EditableText sets back the selection it was just given; only a
      // real move is news.
      final moved = newValue.selection != selection;
      super.value = newValue;
      if (moved) onSelectionChanged?.call(newValue.selection);
      return;
    }
    final edit = onEdit;
    if (edit == null) return;
    // The changed span: everything between the common prefix and suffix,
    // with the prefix kept short of the caret so typing a letter that
    // repeats its neighbor is reported where the caret is.
    var prefix = 0;
    final shortest = old.length < next.length ? old.length : next.length;
    final caret = newValue.selection.isValid
        ? newValue.selection.extentOffset
        : next.length;
    final added = next.length - old.length;
    final prefixLimit =
        added > 0 ? (caret - added).clamp(0, shortest) : shortest;
    while (prefix < prefixLimit && old[prefix] == next[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shortest - prefix &&
        old[old.length - 1 - suffix] == next[next.length - 1 - suffix]) {
      suffix++;
    }
    edit(
      prefix,
      old.length - suffix,
      next.substring(prefix, next.length - suffix),
      newValue,
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final root = layout.rootStyle(_paragraph, scale: scale);
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final spans = <TextSpan>[];
    var offset = 0;
    void add(String text, TextStyle? style) {
      // Split at the composing range's edges to underline it.
      final start = offset;
      final end = offset + text.length;
      offset = end;
      if (!composing.isValid ||
          composing.end <= start ||
          composing.start >= end) {
        spans.add(TextSpan(text: text, style: style));
        return;
      }
      final a = composing.start.clamp(start, end) - start;
      final b = composing.end.clamp(start, end) - start;
      const underline = TextStyle(decoration: TextDecoration.underline);
      spans.addAll([
        if (a > 0) TextSpan(text: text.substring(0, a), style: style),
        TextSpan(
          text: text.substring(a, b),
          style: style?.merge(underline) ?? underline,
        ),
        if (b < text.length) TextSpan(text: text.substring(b), style: style),
      ]);
    }

    if (leadingBreak) add(lineBreak, null);
    for (final run in _paragraph.runs) {
      if (run.text.isEmpty) continue;
      add(run.text, layout.runStyle(run, scale: scale));
    }
    return TextSpan(style: root, children: spans);
  }
}

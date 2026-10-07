import '../model/slide_element.dart';

/// Where a [SlideMatch] was found: in a text box on the slide, or in the
/// slide's speaker notes.
enum SlideMatchField {
  /// The text of a `TextBox`.
  text,

  /// The slide's speaker notes.
  notes,
}

/// One occurrence of a search in a presentation, found by `SlideSearch`.
///
/// [paragraph] counts a text box's paragraphs, or the lines of the notes
/// (split at `\n`); [start] and [end] count UTF-16 code units in that
/// paragraph's plain text, as Dart strings and text selections do. [text]
/// is what matched, so a replace can tell when the document has moved on
/// since the search and skip a match gone stale.
///
/// Matches sort in reading order ([compareTo]): by slide, then the slide's
/// text boxes back to front — a group's children in its place, in their own
/// stacking order — then the notes, then by paragraph and offset.
class SlideMatch implements Comparable<SlideMatch> {
  /// Creates a match.
  const SlideMatch({
    required this.slideId,
    required this.slideIndex,
    required this.field,
    required this.paragraph,
    required this.start,
    required this.end,
    required this.text,
    this.elementPath = const [],
    this.elementOrder = 0,
  });

  /// The id of the slide the match is on.
  final String slideId;

  /// The slide's index in the presentation when the search ran.
  final int slideIndex;

  /// Whether the match is in a text box or in the notes.
  final SlideMatchField field;

  /// The ids from the outermost group down to the text box holding the
  /// match: `['box']` on the slide itself, `['outer', 'inner', 'box']`
  /// inside two groups. Empty for [SlideMatchField.notes].
  final List<String> elementPath;

  /// The text box's place among the slide's text boxes in reading order;
  /// 0 for notes, which sort after every box by [field].
  final int elementOrder;

  /// The index of the paragraph, or notes line, holding the match.
  final int paragraph;

  /// Where the match starts in the paragraph's plain text.
  final int start;

  /// Where the match ends in the paragraph's plain text; past [start].
  final int end;

  /// The characters that matched.
  final String text;

  /// The text box holding the match, or `null` for notes.
  String? get elementId => elementPath.isEmpty ? null : elementPath.last;

  /// The group directly holding the text box, or `null` when it is on the
  /// slide itself or the match is in the notes.
  String? get groupId =>
      elementPath.length < 2 ? null : elementPath[elementPath.length - 2];

  /// Whether this match is in the same text, or the same notes, as [other].
  bool sameTarget(SlideMatch other) =>
      other.slideId == slideId &&
      other.field == field &&
      other.elementId == elementId;

  /// [start] counted in the whole text whose paragraphs (or notes lines)
  /// are [paragraphs], joined by `\n` — a `TextBox.plainText` offset.
  int offsetIn(List<String> paragraphs) {
    var offset = start;
    for (var i = 0; i < paragraph && i < paragraphs.length; i++) {
      offset += paragraphs[i].length + 1;
    }
    return offset;
  }

  /// The plain text of each of [box]'s paragraphs, for [offsetIn].
  static List<String> paragraphsOf(TextBox box) => [
        for (final p in box.paragraphs) p.plainText,
      ];

  @override
  int compareTo(SlideMatch other) {
    for (final (a, b) in [
      (slideIndex, other.slideIndex),
      (field.index, other.field.index),
      (elementOrder, other.elementOrder),
      (paragraph, other.paragraph),
      (start, other.start),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is SlideMatch &&
      other.slideId == slideId &&
      other.slideIndex == slideIndex &&
      other.field == field &&
      other.elementOrder == elementOrder &&
      other.paragraph == paragraph &&
      other.start == start &&
      other.end == end &&
      other.text == text &&
      _samePath(other.elementPath, elementPath);

  static bool _samePath(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        slideId,
        slideIndex,
        field,
        elementOrder,
        paragraph,
        start,
        end,
        text,
        Object.hashAll(elementPath),
      );

  @override
  String toString() =>
      'SlideMatch($slideId, ${field.name}, ${elementPath.join('/')}, '
      '¶$paragraph $start-$end "$text")';
}

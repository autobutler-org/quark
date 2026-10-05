import '../model/presentation.dart';
import '../model/slide_element.dart';
import 'slide_match.dart';
import 'slide_search_query.dart';

/// Which part of a presentation a `SlideSearch` looks through.
class SlideSearchScope {
  /// Looks through every slide, or only [slideId] when given, and through
  /// the speaker notes too when [includeNotes].
  const SlideSearchScope({this.slideId, this.includeNotes = false});

  /// Every slide's text boxes, without notes.
  static const allSlides = SlideSearchScope();

  /// The one slide searched, or `null` for every slide.
  final String? slideId;

  /// Whether speaker notes are searched as well as text boxes.
  final bool includeNotes;

  @override
  bool operator ==(Object other) =>
      other is SlideSearchScope &&
      other.slideId == slideId &&
      other.includeNotes == includeNotes;

  @override
  int get hashCode => Object.hash(slideId, includeNotes);
}

/// What a search found: its [matches] in reading order, or the [error]
/// that kept it from running.
///
/// [truncated] says the search stopped early — at
/// [SlideSearch.maxMatches], or past its time budget — so the count is a
/// lower bound. [next] and [previous] step through [matches], wrapping
/// around at either end.
class SlideSearchResult {
  /// Creates a result.
  const SlideSearchResult({
    this.matches = const [],
    this.error,
    this.truncated = false,
  });

  /// A search that found nothing.
  static const empty = SlideSearchResult();

  /// What was found, in reading order (see [SlideMatch.compareTo]).
  final List<SlideMatch> matches;

  /// Why the query could not run, or `null`.
  final SlideSearchError? error;

  /// Whether the search stopped before looking everywhere.
  final bool truncated;

  /// How many matches there are.
  int get length => matches.length;

  /// Whether nothing was found.
  bool get isEmpty => matches.isEmpty;

  /// The index after [current], wrapping from the last to the first; the
  /// first when [current] is `null`. `null` when there are no matches.
  int? next(int? current) {
    if (matches.isEmpty) return null;
    if (current == null) return 0;
    return (current + 1) % matches.length;
  }

  /// The index before [current], wrapping from the first to the last; the
  /// last when [current] is `null`. `null` when there are no matches.
  int? previous(int? current) {
    if (matches.isEmpty) return null;
    if (current == null) return matches.length - 1;
    return (current - 1 + matches.length) % matches.length;
  }

  /// The index of the first match at or after [match] in reading order,
  /// wrapping to the first; `null` when there are no matches. Where a
  /// search picks up after the document changed under it.
  int? indexFrom(SlideMatch match) {
    if (matches.isEmpty) return null;
    final at = matches.indexWhere((m) => m.compareTo(match) >= 0);
    return at < 0 ? 0 : at;
  }
}

/// Finds text in a [Presentation]: a pure function over the immutable
/// model, with no Flutter dependency.
///
/// It looks through every `TextBox` — inside groups too — and, when the
/// scope asks, each slide's speaker notes, one paragraph (or notes line)
/// at a time, so a match spans runs of different styles but never a line
/// break. Matches do not overlap: `aa` is found once in `aaa`. A pattern
/// that can match nothing, such as `a*`, skips its empty matches.
///
/// ```dart
/// final result = SlideSearch.find(
///   deck,
///   const SlideSearchQuery('revenue', wholeWord: true),
///   scope: const SlideSearchScope(includeNotes: true),
/// );
/// final first = result.matches.firstOrNull;
/// ```
///
/// A regular expression runs only after `SlideSearchQuery.compile` has
/// refused the shapes that backtrack exponentially, and the whole search
/// stops at [maxMatches] or after [timeBudget], marking the result
/// `truncated`.
abstract final class SlideSearch {
  /// The most matches one search returns.
  static const maxMatches = 1000;

  /// How long one search may run before it stops where it is.
  static const timeBudget = Duration(milliseconds: 250);

  /// Searches [presentation] for [query] within [scope].
  static SlideSearchResult find(
    Presentation presentation,
    SlideSearchQuery query, {
    SlideSearchScope scope = SlideSearchScope.allSlides,
  }) {
    final (:pattern, :error) = query.compile();
    if (pattern == null) return SlideSearchResult(error: error);
    final clock = Stopwatch()..start();
    final matches = <SlideMatch>[];
    var truncated = false;

    /// Adds [line]'s matches; false once the search has to stop.
    bool scan(
      String line,
      SlideMatch Function(int start, int end, String text) make,
    ) {
      for (final m in pattern.allMatches(line)) {
        if (m.end == m.start) continue;
        if (matches.length >= maxMatches) {
          truncated = true;
          return false;
        }
        matches.add(make(m.start, m.end, m[0]!));
      }
      if (clock.elapsed <= timeBudget) return true;
      truncated = true;
      return false;
    }

    final slides = presentation.slides;
    search:
    for (var s = 0; s < slides.length; s++) {
      final slide = slides[s];
      if (scope.slideId != null && slide.id != scope.slideId) continue;
      var order = 0;
      for (final (path, box) in _textBoxes(slide.elements, const [])) {
        final elementOrder = order++;
        for (var p = 0; p < box.paragraphs.length; p++) {
          final going = scan(
            box.paragraphs[p].plainText,
            (start, end, text) => SlideMatch(
              slideId: slide.id,
              slideIndex: s,
              field: SlideMatchField.text,
              elementPath: path,
              elementOrder: elementOrder,
              paragraph: p,
              start: start,
              end: end,
              text: text,
            ),
          );
          if (!going) break search;
        }
      }
      if (!scope.includeNotes) continue;
      final lines = slide.notes.split('\n');
      for (var p = 0; p < lines.length; p++) {
        final going = scan(
          lines[p],
          (start, end, text) => SlideMatch(
            slideId: slide.id,
            slideIndex: s,
            field: SlideMatchField.notes,
            paragraph: p,
            start: start,
            end: end,
            text: text,
          ),
        );
        if (!going) break search;
      }
    }
    return SlideSearchResult(
      matches: List.unmodifiable(matches),
      truncated: truncated,
    );
  }

  /// Every text box in [elements], back to front, with its path of ids
  /// from the outermost group down.
  static Iterable<(List<String>, TextBox)> _textBoxes(
    List<SlideElement> elements,
    List<String> up,
  ) sync* {
    for (final e in elements) {
      final path = List<String>.unmodifiable([...up, e.id]);
      switch (e) {
        case TextBox():
          yield (path, e);
        case GroupElement(:final children):
          yield* _textBoxes(children, path);
        default:
      }
    }
  }
}

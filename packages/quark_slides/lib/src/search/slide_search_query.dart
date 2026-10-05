/// Why a [SlideSearchQuery] could not be turned into a pattern.
enum SlideSearchError {
  /// The regular expression does not parse.
  invalidPattern,

  /// The regular expression could take exponential time — a repeated group
  /// that itself repeats, like `(a+)+` — or is longer than
  /// [SlideSearchQuery.maxPatternLength].
  unsafePattern,
}

/// What a `SlideSearch` looks for: [text], and how to match it.
///
/// By default [text] is literal, matched without regard to case. With
/// [regex] it is a regular expression in Dart's Unicode mode; one that
/// does not parse, or that could backtrack for exponential time, is refused
/// with a [SlideSearchError] rather than run. [wholeWord] keeps only
/// matches with no letter, digit or underscore — in any script — right
/// before or after them.
class SlideSearchQuery {
  /// Creates a query.
  const SlideSearchQuery(
    this.text, {
    this.caseSensitive = false,
    this.wholeWord = false,
    this.regex = false,
  });

  /// What to find; an empty query finds nothing.
  final String text;

  /// Whether `Cat` and `cat` differ.
  final bool caseSensitive;

  /// Whether a match must be a whole word.
  final bool wholeWord;

  /// Whether [text] is a regular expression rather than literal.
  final bool regex;

  /// The longest regular expression compiled, in characters.
  static const maxPatternLength = 512;

  /// Whether the query finds nothing because it is empty.
  bool get isEmpty => text.isEmpty;

  /// The pattern this query matches with, or the reason it has none. An
  /// empty query has neither.
  ({RegExp? pattern, SlideSearchError? error}) compile() {
    if (text.isEmpty) return (pattern: null, error: null);
    var source = RegExp.escape(text);
    if (regex) {
      if (text.length > maxPatternLength || repeatsRepetition(text)) {
        return (pattern: null, error: SlideSearchError.unsafePattern);
      }
      try {
        // Checked on its own first, so a stray `)` cannot close the group
        // it is wrapped in below.
        RegExp(text, unicode: true);
      } on FormatException {
        return (pattern: null, error: SlideSearchError.invalidPattern);
      }
      source = '(?:$text)';
    }
    if (wholeWord) {
      source = '(?<![\\p{L}\\p{N}_])$source(?![\\p{L}\\p{N}_])';
    }
    try {
      return (
        pattern: RegExp(source, caseSensitive: caseSensitive, unicode: true),
        error: null,
      );
    } on FormatException {
      return (pattern: null, error: SlideSearchError.invalidPattern);
    }
  }

  /// Whether the regular expression [pattern] repeats a group that already
  /// repeats something — `(a+)+`, `(\w*)*`, `(?:x{2,})+` — the shape that
  /// backtracks for exponential time on a near miss.
  ///
  /// A conservative check over the source: escapes and character classes
  /// are skipped, and a group counts as repeating when anything inside it,
  /// at any depth, carries `*`, `+` or `{n,…}`. A group repeated by `?` or
  /// an exact `{n}` is fine.
  static bool repeatsRepetition(String pattern) {
    final groups = <bool>[];
    var inClass = false;
    var i = 0;
    bool repeatsAt(int at) {
      if (at >= pattern.length) return false;
      final c = pattern[at];
      if (c == '*' || c == '+') return true;
      if (c != '{') return false;
      final close = pattern.indexOf('}', at);
      return close > at && pattern.substring(at, close).contains(',');
    }

    void markRepeat() {
      if (groups.isNotEmpty) groups[groups.length - 1] = true;
    }

    while (i < pattern.length) {
      final c = pattern[i];
      if (c == '\\') {
        if (!inClass && repeatsAt(i + 2)) markRepeat();
        i += 2;
        continue;
      }
      if (inClass) {
        if (c == ']') {
          inClass = false;
          if (repeatsAt(i + 1)) markRepeat();
        }
        i++;
        continue;
      }
      switch (c) {
        case '[':
          inClass = true;
        case '(':
          groups.add(false);
        case ')':
          final inner = groups.isEmpty ? false : groups.removeLast();
          final repeated = repeatsAt(i + 1);
          if (inner && repeated) return true;
          if (inner || repeated) markRepeat();
        case '*' || '+':
          markRepeat();
        case '{':
          if (repeatsAt(i)) markRepeat();
      }
      i++;
    }
    return false;
  }

  /// Returns a copy with the given fields replaced.
  SlideSearchQuery copyWith({
    String? text,
    bool? caseSensitive,
    bool? wholeWord,
    bool? regex,
  }) =>
      SlideSearchQuery(
        text ?? this.text,
        caseSensitive: caseSensitive ?? this.caseSensitive,
        wholeWord: wholeWord ?? this.wholeWord,
        regex: regex ?? this.regex,
      );

  @override
  bool operator ==(Object other) =>
      other is SlideSearchQuery &&
      other.text == text &&
      other.caseSensitive == caseSensitive &&
      other.wholeWord == wholeWord &&
      other.regex == regex;

  @override
  int get hashCode => Object.hash(text, caseSensitive, wholeWord, regex);

  @override
  String toString() => 'SlideSearchQuery("$text")';
}

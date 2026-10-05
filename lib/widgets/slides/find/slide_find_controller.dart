import 'package:flutter/widgets.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark_slides/quark_slides.dart';

/// Which slides the find bar looks through.
enum SlideFindScope {
  /// Every slide in the presentation.
  allSlides,

  /// Only the slide on the canvas.
  currentSlide,
}

/// The state of the slide editor's find bar (#1176): the query and its
/// options, what `SlideSearch` found, which match the bar is on, and the
/// replacement.
///
/// It reads the open presentation through [document] and searches again
/// whenever [source] notifies and the presentation or the slide on the
/// canvas has changed, keeping its place: after an edit it moves to the
/// first match at or after the one it was on. Stepping to a match on
/// another slide calls [showSlide]; the canvas, given [highlights] and
/// [current], selects and centers it.
///
/// [replaceCurrent] and [replaceAll] go through the document controller's
/// commands of the same name, each one undo step.
///
/// ```dart
/// late final find = SlideFindController.forEditor(editorController);
/// ```
class SlideFindController extends ChangeNotifier {
  /// Creates a controller searching [document]'s presentation, refreshed
  /// when [source] notifies.
  SlideFindController({
    required this.source,
    required this.document,
    required this.currentSlideId,
    required this.showSlide,
    this.isReadOnly = _never,
  }) {
    source.addListener(_onSourceChanged);
    query.addListener(_onQueryChanged);
  }

  /// A controller over the slide editor's open presentation and selected
  /// slide.
  factory SlideFindController.forEditor(SlideEditorController editor) =>
      SlideFindController(
        source: editor,
        document: () => editor.document,
        currentSlideId: () => editor.selectedSlideId,
        showSlide: editor.selectSlide,
        isReadOnly: () => editor.isReadOnly,
      );

  static bool _never() => false;

  /// Notifies when the presentation or the slide on the canvas may have
  /// changed.
  final Listenable source;

  /// The open presentation, or `null` while there is none.
  final SlideDocumentNotifier? Function() document;

  /// The slide on the canvas, or `null`.
  final String? Function() currentSlideId;

  /// Puts the slide with this id on the canvas.
  final ValueChanged<String> showSlide;

  /// Whether the presentation is view only: the bar then only searches, with
  /// no replace row and no replacing.
  final bool Function() isReadOnly;

  /// The text to find, typed in the bar.
  final TextEditingController query = TextEditingController();

  /// The text to replace matches with.
  final TextEditingController replacement = TextEditingController();

  /// The query field's focus, so opening the bar again can take it.
  final FocusNode queryFocus = FocusNode(debugLabel: 'SlideFindQuery');

  bool _isOpen = false;
  bool _showReplace = false;
  bool _showOptions = false;
  bool _caseSensitive = false;
  bool _wholeWord = false;
  bool _regex = false;
  bool _includeNotes = false;
  SlideFindScope _scope = SlideFindScope.allSlides;
  SlideSearchResult _result = SlideSearchResult.empty;
  int? _index;
  Presentation? _searched;
  String? _searchedSlide;

  /// Whether the bar is showing.
  bool get isOpen => _isOpen;

  /// Whether the bar shows its replace row.
  bool get showReplace => _showReplace && !isReadOnly();

  /// Whether a phone's bar shows its option chips; a wide bar always does.
  bool get showOptions => _showOptions;

  /// Whether `Cat` and `cat` differ.
  bool get caseSensitive => _caseSensitive;

  /// Whether only whole words match.
  bool get wholeWord => _wholeWord;

  /// Whether the query is a regular expression.
  bool get regex => _regex;

  /// Whether speaker notes are searched too.
  bool get includeNotes => _includeNotes;

  /// Which slides are searched.
  SlideFindScope get scope => _scope;

  /// What the last search found.
  SlideSearchResult get result => _result;

  /// The index in [result] of the match the bar is on, or `null`.
  int? get index => _index;

  /// The match the bar is on, or `null`; `null` while closed.
  SlideMatch? get current {
    final i = _index;
    return !_isOpen || i == null ? null : _result.matches[i];
  }

  /// Every match, for the canvas to highlight; none while closed.
  List<SlideMatch> get highlights => _isOpen ? _result.matches : const [];

  /// Whether [next] and [previous] have anywhere to go.
  bool get canStep => _result.matches.isNotEmpty;

  /// Whether there is a match to replace.
  bool get canReplace => current != null && !isReadOnly();

  /// What the counter reads: `3 of 12`, `No results`, `1000+ results` when
  /// the search stopped early, or why a regular expression did not run.
  /// Empty with no query.
  String get status {
    switch (_result.error) {
      case SlideSearchError.invalidPattern:
        return 'Invalid pattern';
      case SlideSearchError.unsafePattern:
        return 'Pattern too complex';
      case null:
    }
    if (query.text.isEmpty) return '';
    final count = _result.length;
    if (count == 0) return 'No results';
    final total = _result.truncated ? '$count+' : '$count';
    final i = _index;
    return i == null ? '$total results' : '${i + 1} of $total';
  }

  /// Shows the bar — with the replace row when [replace] — and puts the
  /// cursor in the query, its text selected so typing replaces it.
  void open({bool replace = false}) {
    query.selection = TextSelection(
      baseOffset: 0,
      extentOffset: query.text.length,
    );
    _isOpen = true;
    if (replace) _showReplace = true;
    _search(keepFrom: current);
    notifyListeners();
    queryFocus.requestFocus();
  }

  /// Hides the bar and its highlights.
  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    queryFocus.unfocus();
    notifyListeners();
  }

  /// Opens the bar when it is closed and closes it when it is open, as its
  /// bar button does.
  void toggle() => _isOpen ? close() : open();

  /// Shows or hides the replace row.
  void toggleReplace() => _set(() => _showReplace = !_showReplace);

  /// Shows or hides a phone's option chips.
  void toggleOptions() => _set(() => _showOptions = !_showOptions);

  /// Turns case-sensitive matching on or off.
  void toggleCaseSensitive() =>
      _set(() => _caseSensitive = !_caseSensitive, search: true);

  /// Turns whole-word matching on or off.
  void toggleWholeWord() => _set(() => _wholeWord = !_wholeWord, search: true);

  /// Turns regular expressions on or off.
  void toggleRegex() => _set(() => _regex = !_regex, search: true);

  /// Turns searching speaker notes on or off.
  void toggleNotes() =>
      _set(() => _includeNotes = !_includeNotes, search: true);

  /// Searches only the slide on the canvas, or every slide.
  void toggleCurrentSlide() => _set(
    () => _scope = _scope == SlideFindScope.allSlides
        ? SlideFindScope.currentSlide
        : SlideFindScope.allSlides,
    search: true,
  );

  /// Moves to the next match, wrapping to the first.
  void next() => _go(_result.next(_index));

  /// Moves to the previous match, wrapping to the last.
  void previous() => _go(_result.previous(_index));

  /// Replaces the match the bar is on and moves to the next one, as one
  /// undo step.
  void replaceCurrent() {
    final match = current;
    final doc = document();
    if (match == null || doc == null || isReadOnly()) return;
    final text = replacement.text;
    doc.controller.replaceCurrent(match, text);
    // Picks up after the replacement, so one containing the query is not
    // found again.
    _search(
      keepFrom: SlideMatch(
        slideId: match.slideId,
        slideIndex: match.slideIndex,
        field: match.field,
        elementPath: match.elementPath,
        elementOrder: match.elementOrder,
        paragraph: match.paragraph,
        start: match.start + text.length,
        end: match.start + text.length + 1,
        text: '',
      ),
    );
    _follow();
    notifyListeners();
  }

  /// Replaces every match as one undo step, and returns how many were.
  int replaceAll() {
    final doc = document();
    if (doc == null || _result.isEmpty || isReadOnly()) return 0;
    final count = doc.controller.replaceAll(_result.matches, replacement.text);
    _search(keepFrom: current);
    notifyListeners();
    return count;
  }

  String _searchedText = '';

  void _set(VoidCallback change, {bool search = false}) {
    change();
    if (search) _search(keepFrom: current);
    notifyListeners();
  }

  void _go(int? index) {
    if (index == null) return;
    _index = index;
    _follow();
    notifyListeners();
  }

  /// Puts the current match's slide on the canvas.
  void _follow() {
    final match = current;
    if (match != null && match.slideId != currentSlideId()) {
      showSlide(match.slideId);
    }
  }

  void _onQueryChanged() {
    // The controller notifies on every caret move too.
    if (!_isOpen || query.text == _searchedText) return;
    _search(fromCanvas: true);
    _follow();
    notifyListeners();
  }

  void _onSourceChanged() {
    if (!_isOpen) return;
    final presentation = document()?.presentation;
    final slide = currentSlideId();
    final slideMatters = _scope == SlideFindScope.currentSlide;
    if (identical(presentation, _searched) &&
        (!slideMatters || slide == _searchedSlide)) {
      return;
    }
    _search(keepFrom: current);
    notifyListeners();
  }

  /// Searches again, landing on the first match at or after [keepFrom], or
  /// with [fromCanvas] the first on or after the slide on the canvas.
  void _search({SlideMatch? keepFrom, bool fromCanvas = false}) {
    final presentation = document()?.presentation;
    final slide = currentSlideId();
    _searched = presentation;
    _searchedSlide = slide;
    _searchedText = query.text;
    if (presentation == null) {
      _result = SlideSearchResult.empty;
      _index = null;
      return;
    }
    _result = SlideSearch.find(
      presentation,
      SlideSearchQuery(
        query.text,
        caseSensitive: _caseSensitive,
        wholeWord: _wholeWord,
        regex: _regex,
      ),
      scope: SlideSearchScope(
        slideId: _scope == SlideFindScope.currentSlide ? slide : null,
        includeNotes: _includeNotes,
      ),
    );
    final from =
        keepFrom ??
        (fromCanvas && slide != null ? _slideStart(presentation, slide) : null);
    _index = from == null ? _result.next(null) : _result.indexFrom(from);
  }

  /// A position before every match on [slideId].
  static SlideMatch? _slideStart(Presentation presentation, String slideId) {
    final at = presentation.indexOfSlide(slideId);
    if (at < 0) return null;
    return SlideMatch(
      slideId: slideId,
      slideIndex: at,
      field: SlideMatchField.text,
      elementOrder: -1,
      paragraph: 0,
      start: 0,
      end: 0,
      text: '',
    );
  }

  @override
  void dispose() {
    source.removeListener(_onSourceChanged);
    query.dispose();
    replacement.dispose();
    queryFocus.dispose();
    super.dispose();
  }
}

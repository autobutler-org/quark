import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/quark_tokens.dart';
import '../code_highlighter.dart';
import '../code_language.dart';
import '../code_search_match.dart';
import 'code_viewer_footer.dart';
import 'code_viewer_line.dart';

// Font names.
// cspell:ignore Consolas Menlo Roboto

/// A generous count of the monospace columns [line] can take: a tab counts as
/// eight and anything outside ASCII as two, since a wide glyph, or one drawn
/// from a fallback font, is wider than a column.
///
/// The viewer sizes its sideways scroll from it, and uses it to tell that a
/// line certainly fits one row without measuring it.
int codeLineColumns(String line) {
  var columns = 0;
  for (var i = 0; i < line.length; i++) {
    final unit = line.codeUnitAt(i);
    columns += unit == 0x09
        ? 8
        : unit > 0x7F
        ? 2
        : 1;
  }
  return columns;
}

/// The scrolling text of a `QuarkCodeViewer`: a gutter of line numbers beside
/// the highlighted [lines], built lazily, with a footer under the last line
/// while [hasMore].
///
/// With [wrap] off every line is one row and the whole list scrolls sideways
/// to its longest line. With [wrap] on a line takes as many rows as it needs;
/// each line's height is measured once and kept, so scrolling to a line far
/// down the file lands on it exactly.
///
/// When the active match changes, the list jumps to show it. It jumps rather
/// than animates, so reduced motion needs nothing more.
///
/// [onLoadMore] is called when the list comes within a viewport of its end,
/// once for each length of [lines], and by the footer's button.
///
/// Key prefixes: `code_viewer_line_<index>` on each line, and
/// `code_viewer_load_more` on the footer's button.
///
/// ```dart
/// CodeViewerBody(
///   lines: controller.lines,
///   language: CodeLanguage.dart,
///   matches: controller.matches,
///   activeMatch: controller.activeMatch,
///   hasMore: controller.hasMore,
///   onLoadMore: controller.loadMore,
/// );
/// ```
class CodeViewerBody extends StatefulWidget {
  /// Creates the body.
  const CodeViewerBody({
    required this.lines,
    this.language = CodeLanguage.plain,
    this.wrap = false,
    this.matches = const [],
    this.activeMatch,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadMoreError,
    this.onLoadMore,
    super.key,
  });

  /// The file's lines, without trailing newlines. Append-only: the body keeps
  /// what it worked out for the lines it has seen when the list only grows.
  final List<String> lines;

  /// The language to color [lines] in.
  final CodeLanguage language;

  /// Whether a line too long for the width wraps instead of scrolling
  /// sideways.
  final bool wrap;

  /// The search hits to paint, in line order.
  final List<CodeSearchMatch> matches;

  /// The index into [matches] of the hit to draw strongest and keep in view.
  final int? activeMatch;

  /// Whether more of the file is still on the server.
  final bool hasMore;

  /// Whether the next part is being loaded.
  final bool isLoadingMore;

  /// Why the last load failed, rendered as given; null when it did not.
  final String? loadMoreError;

  /// Called to load the next part: when the list scrolls near its end, and
  /// when the footer's button is tapped.
  final VoidCallback? onLoadMore;

  @override
  State<CodeViewerBody> createState() => _CodeViewerBodyState();
}

class _CodeViewerBodyState extends State<CodeViewerBody> {
  static const double _fontSize = 13;
  static const double _lineHeight = 1.5;
  static const List<String> _fontFallback = [
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'DejaVu Sans Mono',
    'Courier New',
  ];
  static const StrutStyle _strut = StrutStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: _fontFallback,
    fontSize: _fontSize,
    height: _lineHeight,
    forceStrutHeight: true,
  );

  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  /// `_startStates[i]` is the lexer state line `i` starts in. Grown on
  /// demand, so building line N lexes the lines above it once, not per frame.
  final List<CodeLineState> _startStates = [CodeLineState.initial];

  /// What is known about the lines seen so far, extended when the list grows.
  int _seenLength = 0;
  String? _firstSeen;
  String? _lastSeen;
  int _maxColumns = 0;

  /// Each line's height with wrap on, null until it is needed. Valid for
  /// [_heightsKey] only.
  List<double?> _heights = [];
  (double, TextScaler)? _heightsKey;

  /// The geometry of the last build, which the scroll math reads.
  TextScaler? _scaler;
  TextStyle _style = const TextStyle();
  double _charWidth = 0;
  double _rowHeight = 0;
  double _gutterWidth = 0;
  double _textWidth = 0;

  /// The `lines.length` [CodeViewerBody.onLoadMore] was last called for by
  /// scrolling, so one length asks once.
  int? _loadMoreAskedAt;

  @override
  void initState() {
    super.initState();
    _vertical.addListener(_maybeLoadMore);
    _afterFrame(reveal: true);
  }

  @override
  void didUpdateWidget(CodeViewerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      _startStates
        ..clear()
        ..add(CodeLineState.initial);
    }
    // Compared by value, so the same hit in a recomputed list (more lines
    // loaded) does not pull the view back to it.
    _afterFrame(
      reveal:
          _activeOf(oldWidget) != _activeOf(widget) ||
          oldWidget.wrap != widget.wrap,
    );
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  static CodeSearchMatch? _activeOf(CodeViewerBody widget) {
    final index = widget.activeMatch;
    return index != null && index >= 0 && index < widget.matches.length
        ? widget.matches[index]
        : null;
  }

  /// Scroll work waits for the frame, when the list has its new layout.
  void _afterFrame({required bool reveal}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (reveal) _revealActiveMatch();
      _maybeLoadMore();
    });
  }

  /// Brings the caches in step with the lines: extended when the list only
  /// grew, dropped when it is a different file.
  void _syncLines() {
    final lines = widget.lines;
    // ponytail: "only grew" is judged from the first and last lines already
    // seen, not the whole prefix. Compare every line if a caller ever edits
    // the middle of a file in place.
    final grew =
        lines.length >= _seenLength &&
        (_seenLength == 0 ||
            (lines.first == _firstSeen && lines[_seenLength - 1] == _lastSeen));
    if (!grew) {
      _startStates
        ..clear()
        ..add(CodeLineState.initial);
      _heights = [];
      _maxColumns = 0;
      _seenLength = 0;
      _loadMoreAskedAt = null;
    }
    for (var i = _seenLength; i < lines.length; i++) {
      _maxColumns = math.max(_maxColumns, codeLineColumns(lines[i]));
    }
    _heights.length = lines.length;
    _seenLength = lines.length;
    _firstSeen = lines.firstOrNull;
    _lastSeen = lines.lastOrNull;
  }

  CodeLineState _startStateOf(int index) {
    while (_startStates.length <= index) {
      final at = _startStates.length - 1;
      _startStates.add(
        highlightCodeLine(
          widget.lines[at],
          widget.language,
          _startStates[at],
        ).endState,
      );
    }
    return _startStates[index];
  }

  double _heightOf(int index) {
    if (!widget.wrap) return _rowHeight;
    return _heights[index] ??= _measure(widget.lines[index]);
  }

  double _measure(String line) {
    // Certainly one row: no need to lay it out.
    if (codeLineColumns(line) * _charWidth <= _textWidth) return _rowHeight;
    final painter = TextPainter(
      text: TextSpan(text: line, style: _style),
      textDirection: TextDirection.ltr,
      textScaler: _scaler ?? TextScaler.noScaling,
      strutStyle: _strut,
    )..layout(maxWidth: _textWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  void _revealActiveMatch() {
    final match = _activeOf(widget);
    final count = widget.lines.length;
    if (match == null ||
        match.line < 0 ||
        match.line >= count ||
        !_vertical.hasClients) {
      return;
    }
    final position = _vertical.position;
    final viewport = position.viewportDimension;
    var top = 0.0;
    for (var i = 0; i < match.line; i++) {
      top += _heightOf(i);
    }
    final height = _heightOf(match.line);
    if (top < position.pixels || top + height > position.pixels + viewport) {
      // A third of the way down, or higher when the line is too tall for
      // that. If the file ends first, as far as the lines go, which is never
      // past the end of the scroll.
      final lead = math.max(0.0, math.min(viewport / 3, viewport - height));
      var tail = 0.0;
      for (var i = match.line; i < count && tail < viewport; i++) {
        tail += _heightOf(i);
      }
      _vertical.jumpTo(
        math.max(0.0, math.min(top - lead, top + tail - viewport)),
      );
    }

    if (widget.wrap || !_horizontal.hasClients) return;
    final sideways = _horizontal.position;
    final start = _gutterWidth + match.start * _charWidth;
    final end = _gutterWidth + match.end * _charWidth;
    if (start < sideways.pixels ||
        end > sideways.pixels + sideways.viewportDimension) {
      _horizontal.jumpTo(
        math.min(
          sideways.maxScrollExtent,
          math.max(0.0, start - sideways.viewportDimension / 2),
        ),
      );
    }
  }

  void _maybeLoadMore() {
    final onLoadMore = widget.onLoadMore;
    if (!mounted ||
        onLoadMore == null ||
        !widget.hasMore ||
        widget.isLoadingMore ||
        widget.loadMoreError != null ||
        _loadMoreAskedAt == widget.lines.length ||
        !_vertical.hasClients) {
      return;
    }
    final position = _vertical.position;
    if (position.extentAfter > position.viewportDimension) return;
    _loadMoreAskedAt = widget.lines.length;
    onLoadMore();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final lines = widget.lines;
    final active = _activeOf(widget);
    final matchesByLine = <int, List<CodeSearchMatch>>{};
    for (final match in widget.matches) {
      (matchesByLine[match.line] ??= []).add(match);
    }

    _style = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: _fontFallback,
      fontSize: _fontSize,
      height: _lineHeight,
      color: tokens.foreground,
    );
    if (scaler != _scaler) {
      final probe = TextPainter(
        text: TextSpan(text: '0' * 16, style: _style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        strutStyle: _strut,
      )..layout();
      _charWidth = probe.width / 16;
      _rowHeight = probe.height;
      probe.dispose();
      _scaler = scaler;
    }
    _syncLines();
    final digits = math.max(3, '${lines.length}'.length);
    _gutterWidth = tokens.spacingSm + digits * _charWidth + tokens.spacingMd;
    final chrome = _gutterWidth + tokens.spacingMd;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        // One spare column, so a rounding error never clips the last glyph.
        final contentWidth = widget.wrap
            ? viewportWidth
            : math.max(viewportWidth, chrome + (_maxColumns + 1) * _charWidth);
        _textWidth = math.max(_charWidth, contentWidth - chrome);
        final heightsKey = (_textWidth, scaler);
        if (heightsKey != _heightsKey) {
          _heights = List.filled(lines.length, null, growable: true);
          _heightsKey = heightsKey;
        }

        Widget lineAt(BuildContext context, int index) => CodeViewerLine(
          key: ValueKey('code_viewer_line_$index'),
          index: index,
          text: lines[index],
          tokens: highlightCodeLine(
            lines[index],
            widget.language,
            _startStateOf(index),
          ).tokens,
          matches: matchesByLine[index] ?? const [],
          activeMatch: active?.line == index ? active : null,
          gutterWidth: _gutterWidth,
          style: _style,
          strutStyle: _strut,
          wrap: widget.wrap,
        );

        return ScrollConfiguration(
          // The two scrollbars below are the only ones: the platform's own
          // would draw the vertical one at the far end of the longest line.
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: Scrollbar(
            controller: _vertical,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.vertical,
            child: Scrollbar(
              controller: _horizontal,
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentWidth,
                  child: SelectionArea(
                    child: CustomScrollView(
                      controller: _vertical,
                      slivers: [
                        if (widget.wrap)
                          SliverVariedExtentList.builder(
                            itemCount: lines.length,
                            itemExtentBuilder: (index, _) =>
                                index < lines.length ? _heightOf(index) : null,
                            itemBuilder: lineAt,
                          )
                        else
                          SliverFixedExtentList.builder(
                            itemCount: lines.length,
                            itemExtent: _rowHeight,
                            itemBuilder: lineAt,
                          ),
                        if (widget.hasMore || widget.loadMoreError != null)
                          SliverToBoxAdapter(
                            // Under the visible part, not centered on the
                            // longest line.
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: viewportWidth,
                                child: CodeViewerFooter(
                                  isLoadingMore: widget.isLoadingMore,
                                  loadMoreError: widget.loadMoreError,
                                  onLoadMore: widget.onLoadMore,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

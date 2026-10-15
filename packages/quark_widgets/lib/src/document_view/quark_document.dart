import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The horizontal alignment of a document paragraph.
enum QuarkDocumentAlignment {
  /// Align text with the leading edge of a left-to-right document.
  left,

  /// Center text between both edges.
  center,

  /// Align text with the trailing edge of a left-to-right document.
  right,

  /// Expand spacing so text reaches both edges.
  justify,
}

/// Immutable metadata from the first line of a document preview stream.
@immutable
class QuarkDocumentMetadata {
  /// Creates document metadata.
  const QuarkDocumentMetadata({
    required this.version,
    required this.format,
    this.title,
  });

  /// The block protocol version.
  final int version;

  /// The source format, such as `docx`, `odt`, or `rtf`.
  final String format;

  /// The title stored in the document, when it has one.
  final String? title;
}

/// Counts and warnings from the last line of a document preview stream.
@immutable
class QuarkDocumentSummary {
  /// Creates a document summary.
  const QuarkDocumentSummary({
    required this.truncated,
    required this.words,
    required this.characters,
    required this.paragraphs,
    this.pages,
    this.warnings = const [],
  });

  /// Whether the server stopped at a preview limit.
  final bool truncated;

  /// The words in the parsed portion of the document.
  final int words;

  /// The characters in the parsed portion of the document.
  final int characters;

  /// The paragraphs in the parsed portion of the document.
  final int paragraphs;

  /// The pages emitted before a preview limit, when the reader knows it.
  final int? pages;

  /// Non-fatal losses reported by the document reader.
  final List<String> warnings;
}

/// One styled text run in a paragraph, heading, or list item.
@immutable
class QuarkDocumentRun {
  /// Creates a styled run.
  const QuarkDocumentRun({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.superscript = false,
    this.subscript = false,
    this.link,
    this.linkIndex,
  });

  /// The literal text to render.
  final String text;

  /// Whether the text is bold.
  final bool bold;

  /// Whether the text is italic.
  final bool italic;

  /// Whether the text is underlined.
  final bool underline;

  /// Whether the text is struck through.
  final bool strike;

  /// Whether the text uses the monospace code style.
  final bool code;

  /// Whether the text is superscript.
  final bool superscript;

  /// Whether the text is subscript.
  final bool subscript;

  /// The destination written in the document, or null for plain text.
  final String? link;

  /// The link's position in document order, used for its stable key.
  final int? linkIndex;
}

/// One displayed block in a document preview.
sealed class QuarkDocumentBlock {
  const QuarkDocumentBlock();

  /// Parses one block object independently.
  factory QuarkDocumentBlock.fromJson(Map<String, dynamic> json) =>
      _QuarkDocumentParser().block(json);
}

/// A paragraph made of styled runs.
@immutable
class QuarkDocumentParagraph extends QuarkDocumentBlock {
  /// Creates a paragraph.
  const QuarkDocumentParagraph({
    required this.runs,
    this.alignment = QuarkDocumentAlignment.left,
  });

  /// The runs in source order.
  final List<QuarkDocumentRun> runs;

  /// The paragraph's horizontal alignment.
  final QuarkDocumentAlignment alignment;
}

/// A level-one through level-six heading.
@immutable
class QuarkDocumentHeading extends QuarkDocumentBlock {
  /// Creates a heading.
  const QuarkDocumentHeading({required this.level, required this.runs});

  /// The heading level, from 1 through 6.
  final int level;

  /// The runs in source order.
  final List<QuarkDocumentRun> runs;
}

/// One ordered or unordered list item.
@immutable
class QuarkDocumentListItem extends QuarkDocumentBlock {
  /// Creates a list item.
  const QuarkDocumentListItem({
    required this.ordered,
    required this.level,
    required this.marker,
    required this.runs,
  });

  /// Whether this item belongs to an ordered list.
  final bool ordered;

  /// The zero-based nesting level.
  final int level;

  /// The marker emitted by the reader, such as `1.` or `•`.
  final String marker;

  /// The item's styled text.
  final List<QuarkDocumentRun> runs;
}

/// A table whose cells may span rows and columns and contain blocks.
@immutable
class QuarkDocumentTable extends QuarkDocumentBlock {
  /// Creates a table.
  const QuarkDocumentTable({required this.rows});

  /// The rows in source order.
  final List<QuarkDocumentTableRow> rows;
}

/// One row in a document table.
@immutable
class QuarkDocumentTableRow {
  /// Creates a table row.
  const QuarkDocumentTableRow({required this.cells});

  /// The cells in source order.
  final List<QuarkDocumentTableCell> cells;
}

/// One table cell and the blocks it contains.
@immutable
class QuarkDocumentTableCell {
  /// Creates a table cell.
  const QuarkDocumentTableCell({
    required this.colSpan,
    required this.rowSpan,
    required this.blocks,
  });

  /// The number of columns occupied by this cell.
  final int colSpan;

  /// The number of rows occupied by this cell.
  final int rowSpan;

  /// The cell's blocks in source order.
  final List<QuarkDocumentBlock> blocks;
}

/// An image stored in the document, or an external image that is not loaded.
@immutable
class QuarkDocumentImage extends QuarkDocumentBlock {
  /// Creates an image block.
  const QuarkDocumentImage({
    this.part,
    this.external = false,
    this.alt = '',
    this.width,
    this.height,
  });

  /// The package part to hand to the caller's image builder.
  final String? part;

  /// Whether the source image points outside the document package.
  final bool external;

  /// The image's alternative text.
  final String alt;

  /// The authored width, when known.
  final double? width;

  /// The authored height, when known.
  final double? height;
}

/// Content that the safe preview intentionally did not render.
@immutable
class QuarkDocumentOmitted extends QuarkDocumentBlock {
  /// Creates an omitted-content marker.
  const QuarkDocumentOmitted({required this.what});

  /// A short name for what was left out.
  final String what;
}

/// A page boundary in the source document.
@immutable
class QuarkDocumentPageBreak extends QuarkDocumentBlock {
  /// Creates a page boundary.
  const QuarkDocumentPageBreak();
}

/// A parsed read-only office document, ready for `QuarkDocumentView`.
///
/// [parse] accepts the NDJSON returned by `/previews/document`. It requires a
/// `meta` first line and an `end` last line: a stream cut short by an error is
/// rejected instead of being mistaken for a complete document.
///
/// ```dart
/// final document = QuarkDocument.parse(responseBody);
/// ```
@immutable
class QuarkDocument {
  /// Creates an empty value for the time before a document has loaded.
  const QuarkDocument.empty()
    : metadata = null,
      blocks = const [],
      summary = null;

  const QuarkDocument._({
    required this.metadata,
    required this.blocks,
    required this.summary,
  });

  /// Parses a complete NDJSON preview.
  factory QuarkDocument.parse(String source) =>
      QuarkDocument.fromLines(const LineSplitter().convert(source));

  /// Parses the lines of a complete NDJSON preview.
  factory QuarkDocument.fromLines(Iterable<String> lines) {
    final objects = <Map<String, dynamic>>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final value = jsonDecode(line);
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Document line must be a JSON object.');
      }
      objects.add(value);
    }
    if (objects.isEmpty || objects.first['type'] != 'meta') {
      throw const FormatException('Document preview is missing metadata.');
    }
    if (objects.length < 2 || objects.last['type'] != 'end') {
      throw const FormatException('Document preview ended before its summary.');
    }
    if (objects
        .skip(1)
        .take(objects.length - 2)
        .any((object) => object['type'] == 'meta' || object['type'] == 'end')) {
      throw const FormatException('Document metadata or summary is misplaced.');
    }

    final parser = _QuarkDocumentParser();
    return QuarkDocument._(
      metadata: parser.metadata(objects.first),
      blocks: List.unmodifiable(
        objects.skip(1).take(objects.length - 2).map(parser.block),
      ),
      summary: parser.summary(objects.last),
    );
  }

  /// Metadata from the stream, or null for [QuarkDocument.empty].
  final QuarkDocumentMetadata? metadata;

  /// The top-level blocks in source order.
  final List<QuarkDocumentBlock> blocks;

  /// The final counts and warnings, or null for [QuarkDocument.empty].
  final QuarkDocumentSummary? summary;

  /// Whether the document contains no displayed blocks.
  bool get isEmpty => blocks.isEmpty;
}

class _QuarkDocumentParser {
  int _nextLinkIndex = 0;

  QuarkDocumentMetadata metadata(Map<String, dynamic> json) {
    final version = _integer(json, 'version');
    final format = _string(json, 'format');
    return QuarkDocumentMetadata(
      version: version,
      format: format,
      title: _optionalString(json, 'title'),
    );
  }

  QuarkDocumentSummary summary(Map<String, dynamic> json) =>
      QuarkDocumentSummary(
        truncated: _boolean(json, 'truncated'),
        words: _integer(json, 'words'),
        characters: _integer(json, 'characters'),
        paragraphs: _integer(json, 'paragraphs'),
        pages: _optionalInteger(json, 'pages'),
        warnings: List.unmodifiable(_strings(json, 'warnings')),
      );

  QuarkDocumentBlock block(Map<String, dynamic> json) {
    switch (_string(json, 'type')) {
      case 'paragraph':
        return QuarkDocumentParagraph(
          runs: _runs(json),
          alignment: _alignment(json['align']),
        );
      case 'heading':
        final level = _integer(json, 'level');
        if (level < 1 || level > 6) {
          throw FormatException(
            'Heading level must be from 1 through 6: $level',
          );
        }
        return QuarkDocumentHeading(level: level, runs: _runs(json));
      case 'listItem':
        final level = _integer(json, 'level');
        if (level < 0) {
          throw FormatException('List level cannot be negative: $level');
        }
        return QuarkDocumentListItem(
          ordered: _boolean(json, 'ordered'),
          level: level,
          marker: _string(json, 'marker'),
          runs: _runs(json),
        );
      case 'table':
        return QuarkDocumentTable(
          rows: List.unmodifiable(
            _objects(json, 'rows').map(
              (row) => QuarkDocumentTableRow(
                cells: List.unmodifiable(
                  _objects(row, 'cells').map((cell) {
                    final colSpan = _integer(cell, 'colSpan');
                    final rowSpan = _integer(cell, 'rowSpan');
                    if (colSpan < 1 || rowSpan < 1) {
                      throw const FormatException(
                        'Table spans must be positive.',
                      );
                    }
                    return QuarkDocumentTableCell(
                      colSpan: colSpan,
                      rowSpan: rowSpan,
                      blocks: List.unmodifiable(
                        _objects(cell, 'blocks').map(block),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        );
      case 'image':
        return QuarkDocumentImage(
          part: _optionalString(json, 'part'),
          external: json['external'] == true,
          alt: _optionalString(json, 'alt') ?? '',
          width: _optionalNumber(json, 'width'),
          height: _optionalNumber(json, 'height'),
        );
      case 'omitted':
        return QuarkDocumentOmitted(what: _string(json, 'what'));
      case 'pageBreak':
        return const QuarkDocumentPageBreak();
      default:
        throw FormatException('Unknown document block type: ${json['type']}');
    }
  }

  List<QuarkDocumentRun> _runs(Map<String, dynamic> json) => List.unmodifiable(
    _objects(json, 'runs').map((run) {
      final link = _optionalString(run, 'link');
      return QuarkDocumentRun(
        text: _string(run, 'text'),
        bold: run['bold'] == true,
        italic: run['italic'] == true,
        underline: run['underline'] == true,
        strike: run['strike'] == true,
        code: run['code'] == true,
        superscript: run['superscript'] == true,
        subscript: run['subscript'] == true,
        link: link,
        linkIndex: link == null ? null : _nextLinkIndex++,
      );
    }),
  );

  QuarkDocumentAlignment _alignment(Object? value) => switch (value) {
    null || 'left' => QuarkDocumentAlignment.left,
    'center' => QuarkDocumentAlignment.center,
    'right' => QuarkDocumentAlignment.right,
    'justify' => QuarkDocumentAlignment.justify,
    _ => throw FormatException('Unknown paragraph alignment: $value'),
  };

  String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) return value;
    throw FormatException('Document field "$key" must be a string.');
  }

  String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('Document field "$key" must be a string.');
  }

  bool _boolean(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) return value;
    throw FormatException('Document field "$key" must be a boolean.');
  }

  int _integer(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    throw FormatException('Document field "$key" must be an integer.');
  }

  int? _optionalInteger(Map<String, dynamic> json, String key) {
    if (json[key] == null) return null;
    return _integer(json, key);
  }

  double? _optionalNumber(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw FormatException('Document field "$key" must be a number.');
  }

  Iterable<Map<String, dynamic>> _objects(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! List) {
      throw FormatException('Document field "$key" must be a list.');
    }
    return value.map((item) {
      if (item is Map<String, dynamic>) return item;
      throw FormatException('Items in document field "$key" must be objects.');
    });
  }

  Iterable<String> _strings(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('Document field "$key" must contain strings.');
    }
    return value.cast<String>();
  }
}

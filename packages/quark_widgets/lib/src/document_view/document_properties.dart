import 'package:flutter/foundation.dart';

/// Metadata shown by `QuarkDocumentProperties`.
///
/// ```dart
/// final properties = DocumentProperties.fromJson(responseJson);
/// ```
@immutable
class DocumentProperties {
  /// Creates document properties.
  const DocumentProperties({
    this.title,
    this.author,
    this.subject,
    this.created,
    this.modified,
    this.pages,
    this.words,
    this.characters,
    this.slides,
    this.sheets,
    this.application,
    this.countsSource,
  });

  /// Parses the `/previews/properties` response.
  factory DocumentProperties.fromJson(Map<String, dynamic> json) =>
      DocumentProperties(
        title: _string(json, 'title'),
        author: _string(json, 'author'),
        subject: _string(json, 'subject'),
        created: _date(json, 'created'),
        modified: _date(json, 'modified'),
        pages: _integer(json, 'pages'),
        words: _integer(json, 'words'),
        characters: _integer(json, 'characters'),
        slides: _integer(json, 'slides'),
        sheets: _integer(json, 'sheets'),
        application: _string(json, 'application'),
        countsSource: _string(json, 'countsSource'),
      );

  /// The saved document title.
  final String? title;

  /// The saved author.
  final String? author;

  /// The saved subject.
  final String? subject;

  /// When the document was created.
  final DateTime? created;

  /// When the document was last modified.
  final DateTime? modified;

  /// The saved or parsed page count.
  final int? pages;

  /// The saved or parsed word count.
  final int? words;

  /// The saved or parsed character count.
  final int? characters;

  /// The presentation's slide count.
  final int? slides;

  /// The workbook's sheet count.
  final int? sheets;

  /// The application that last saved the counts.
  final String? application;

  /// Where counts came from, normally `saved` or `parsed`.
  final String? countsSource;

  /// Whether there is at least one property to display.
  bool get isEmpty =>
      title == null &&
      author == null &&
      subject == null &&
      created == null &&
      modified == null &&
      pages == null &&
      words == null &&
      characters == null &&
      slides == null &&
      sheets == null &&
      application == null;

  static String? _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('Property "$key" must be a string.');
  }

  static int? _integer(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is int) return value;
    throw FormatException('Property "$key" must be an integer.');
  }

  static DateTime? _date(Map<String, dynamic> json, String key) {
    final value = _string(json, key);
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
    throw FormatException('Property "$key" must be an ISO 8601 date.');
  }
}

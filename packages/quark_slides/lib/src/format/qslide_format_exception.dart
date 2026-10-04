/// Thrown when a `.qslide` document cannot be read: it is not JSON, a
/// required field is missing or mistyped, or it was written by a newer
/// schema than this package understands.
class QslideFormatException implements Exception {
  /// Creates an exception describing what was wrong and where.
  const QslideFormatException(this.message, {this.path = r'$'});

  /// What was wrong with the document.
  final String message;

  /// A JSONPath-like location of the offending value, such as
  /// `$.slides[2].elements[0].frame`.
  final String path;

  @override
  String toString() => 'QslideFormatException at $path: $message';
}

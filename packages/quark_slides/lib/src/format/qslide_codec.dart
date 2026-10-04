import 'dart:convert';

import '../model/presentation.dart';
import 'json_fields.dart';
import 'qslide_format_exception.dart';

/// Reads and writes `.qslide`, the file a presentation is saved as.
///
/// A `.qslide` file is UTF-8 JSON: one object holding an integer
/// `schemaVersion` beside the fields of [Presentation.toJson].
///
/// ```json
/// {"schemaVersion": 1, "title": "Demo",
///  "size": {"width": 1920, "height": 1080},
///  "slides": [{"id": "s1", "elements": []}]}
/// ```
///
/// Compatibility works in two directions:
///
/// - **Additive changes keep the version.** A field a newer writer adds is
///   carried through every object's `extra` and written back on save, and
///   an element of an unknown `type` is kept verbatim as an
///   `UnknownElement`. An older reader can open, edit and save the file
///   without losing what it did not understand.
/// - **Breaking changes bump it.** A file whose `schemaVersion` is above
///   [schemaVersion] is refused with a [QslideFormatException] rather than
///   misread, so the host can tell the user to update.
abstract final class QslideCodec {
  /// The schema version this package writes and the newest it reads.
  static const schemaVersion = 1;

  /// The file extension, including the dot.
  static const fileExtension = '.qslide';

  /// Parses the text of a `.qslide` file.
  ///
  /// Throws a [QslideFormatException] when [source] is not JSON, has no
  /// usable `schemaVersion`, is newer than [schemaVersion], or has a
  /// missing or mistyped field.
  static Presentation decode(String source) {
    final Object? root;
    try {
      root = jsonDecode(source);
    } on FormatException catch (e) {
      throw QslideFormatException('not JSON: ${e.message}');
    }
    return fromJson(root);
  }

  /// Reads a presentation from an already-decoded `.qslide` root object.
  static Presentation fromJson(Object? root) {
    final json = asObject(root, r'$');
    final version = json['schemaVersion'];
    if (version is! int || version < 1) {
      throw const QslideFormatException(
        'expected a positive integer',
        path: r'$.schemaVersion',
      );
    }
    if (version > schemaVersion) {
      throw QslideFormatException(
        'written by schema version $version; this reader supports up to '
        '$schemaVersion',
        path: r'$.schemaVersion',
      );
    }
    return Presentation.fromJson(json);
  }

  /// The `.qslide` root object for [presentation].
  static JsonMap toJson(Presentation presentation) => {
        'schemaVersion': schemaVersion,
        ...presentation.toJson(),
      };

  /// The text of a `.qslide` file for [presentation], indented two spaces
  /// so that saved files diff cleanly.
  static String encode(Presentation presentation) =>
      '${const JsonEncoder.withIndent('  ').convert(toJson(presentation))}\n';
}

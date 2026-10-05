import 'dart:convert';

import '../model/presentation.dart';
import '../theme/slide_themes.dart';
import 'json_fields.dart';
import 'qslide_format_exception.dart';

/// Reads and writes `.qslide`, the file a presentation is saved as.
///
/// A `.qslide` file is UTF-8 JSON: one object holding an integer
/// `schemaVersion` beside the fields of [Presentation.toJson].
///
/// ```json
/// {"schemaVersion": 4, "title": "Demo",
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
/// - **Older files are migrated.** A file below [schemaVersion] is brought
///   up to it one version at a time as it is read, and saved at the new
///   version. Version 1 named its theme by a string and had no layouts or
///   theme colors: its theme becomes the built-in one of that id, or none,
///   and every slide is blank-layout. Version 2 had no transitions: every
///   slide cuts, which is what a version 3 file without them means too.
///   Version 3 had no tables, so it reads as it is.
abstract final class QslideCodec {
  /// The schema version this package writes and the newest it reads.
  ///
  /// Version 2 added the inline theme, theme role colors (`theme:accent1`),
  /// slide layouts and text box slots. Version 3 added slide transitions:
  /// a slide's own `transition` and the deck's default one. Version 4 added
  /// tables (`TableElement`); it is a new version rather than an additive
  /// change so that a reader that would draw a table as an unknown
  /// placeholder asks to be updated instead.
  static const schemaVersion = 4;

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
    var migrated = json;
    for (var v = version; v < schemaVersion; v++) {
      migrated = _migrations[v]!(migrated);
    }
    return Presentation.fromJson(migrated);
  }

  /// Upgrades a root object from the version it is keyed by to the next.
  static final Map<int, JsonMap Function(JsonMap)> _migrations = {
    1: _fromVersion1,
    2: _fromVersion2,
    3: _fromVersion3,
  };

  /// Version 1 to 2: the `theme` string — "its id or file path", which no
  /// version 1 reader drew — becomes the built-in theme with that id, or no
  /// theme. Slides without a `layout` are already blank-layout.
  static JsonMap _fromVersion1(JsonMap json) {
    final theme = json['theme'];
    final builtIn = theme is String ? SlideThemes.byId(theme) : null;
    return {
      ...json,
      'schemaVersion': 2,
      'theme': builtIn?.toJson(),
    }..removeWhere((key, value) => key == 'theme' && value == null);
  }

  /// Version 2 to 3: transitions are new, and a deck without any cuts from
  /// slide to slide as version 2 did, so only the version changes. A
  /// `transition` a version 2 file carried as an unknown field is read as
  /// one from here on.
  static JsonMap _fromVersion2(JsonMap json) => {...json, 'schemaVersion': 3};

  /// Version 3 to 4: tables are new, and nothing a version 3 file holds
  /// changes meaning, so only the version changes. An element of `type`
  /// `table` that a version 3 file carried — none was ever written — is
  /// read as a table from here on.
  static JsonMap _fromVersion3(JsonMap json) => {...json, 'schemaVersion': 4};

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

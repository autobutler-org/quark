import 'dart:convert';

import '../model/slide_element.dart';
import 'json_fields.dart';
import 'qslide_format_exception.dart';

/// Writes copied slide elements as clipboard text, and reads them back.
///
/// The text is a small versioned JSON object holding each element as its
/// `.qslide` object, frames on the slide, so a paste works across slides,
/// presentations and app sessions — anything that shares the clipboard:
///
/// ```json
/// {"format": "quark-slides/elements", "version": 1,
///  "elements": [{"id": "e1", "type": "shape", "kind": "ellipse",
///                "frame": {"x": 100, "y": 80, "width": 400, "height": 300}}]}
/// ```
///
/// Versioning follows `.qslide`: an additive change keeps [version], and an
/// element or field this version does not know survives as an
/// `UnknownElement` or in `extra`. A breaking change bumps [version], and
/// a reader refuses a newer payload rather than misreading it.
abstract final class SlideClipboardCodec {
  /// The `format` marker that tells this payload from other text.
  static const format = 'quark-slides/elements';

  /// The payload version this package writes and the newest it reads.
  static const version = 1;

  /// The clipboard text for [elements].
  static String encode(List<SlideElement> elements) => jsonEncode({
        'format': format,
        'version': version,
        'elements': [for (final e in elements) e.toJson()],
      });

  /// The elements in [text], or `null` when [text] is not a payload of
  /// this format — plain text copied from somewhere else.
  ///
  /// Throws a [QslideFormatException] when it is one but cannot be read: a
  /// newer [version], or an element missing a required field.
  static List<SlideElement>? decode(String text) {
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('{')) return null;
    final Object? root;
    try {
      root = jsonDecode(trimmed);
    } on FormatException {
      return null;
    }
    if (root is! Map || root['format'] != format) return null;
    final json = asObject(root, r'$');
    final written = json['version'];
    if (written is! int || written < 1 || written > version) {
      throw QslideFormatException(
        'clipboard version $written; this reader supports up to $version',
        path: r'$.version',
      );
    }
    final elements = optionalList(json, 'elements', r'$');
    return [
      for (var i = 0; i < elements.length; i++)
        SlideElement.fromJson(elements[i], '\$.elements[$i]'),
    ];
  }
}

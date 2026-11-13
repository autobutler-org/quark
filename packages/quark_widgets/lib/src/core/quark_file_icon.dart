import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../models/quark_file_kind.dart';

/// The glyph for a file or folder of the given [kind].
///
/// The caller decides what an entry is, so the glyph always agrees with
/// whatever else the caller decides from that answer, such as which viewer
/// opens it: `QuarkFileIcon(kind: QuarkFileKind.image)`.
///
/// Emits no `ValueKey`s; it is decoration inside a row that carries its own.
///
/// ```dart
/// QuarkFileIcon(kind: QuarkFileKind.qsheet, size: 24);
/// ```
class QuarkFileIcon extends StatelessWidget {
  /// Creates the icon for an entry of [kind].
  const QuarkFileIcon({
    required this.kind,
    this.size = 20.0,
    this.color,
    super.key,
  });

  /// What the entry is, which picks the glyph.
  final QuarkFileKind kind;

  /// The rendered glyph size in logical pixels.
  final double size;

  /// The glyph color. Defaults to the ambient [IconTheme] color.
  final Color? color;

  /// The icon for an entry of [kind], without building a widget.
  ///
  /// Exposed for callers that need the glyph on its own: a list tile's
  /// leading slot, a menu entry, a drag feedback layer.
  static IconData iconFor(QuarkFileKind kind) => switch (kind) {
    QuarkFileKind.folder => QuarkIcons.folder,
    QuarkFileKind.image => QuarkIcons.image_outlined,
    QuarkFileKind.video => QuarkIcons.video_file_outlined,
    QuarkFileKind.audio => QuarkIcons.audio_file_outlined,
    QuarkFileKind.pdf => QuarkIcons.picture_as_pdf_outlined,
    QuarkFileKind.archive => QuarkIcons.archive_outlined,
    QuarkFileKind.qdoc => QuarkIcons.edit_document,
    QuarkFileKind.qsheet => QuarkIcons.table_chart,
    QuarkFileKind.qslide => QuarkIcons.slideshow,
    QuarkFileKind.document => QuarkIcons.description_outlined,
    QuarkFileKind.spreadsheet => QuarkIcons.table_chart_outlined,
    QuarkFileKind.presentation => QuarkIcons.slideshow_outlined,
    QuarkFileKind.generic => QuarkIcons.insert_drive_file_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Icon(iconFor(kind), size: size, color: color);
  }
}

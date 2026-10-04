import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// The glyph for a file or folder, chosen from its name.
///
/// The package takes the name and the directory flag rather than an app model,
/// so callers map their own node type at the call site:
/// `QuarkFileIcon(name: node.name, isDir: node.isDir)`.
///
/// Emits no `ValueKey`s; it is decoration inside a row that carries its own.
///
/// ```dart
/// QuarkFileIcon(name: 'budget.qsheet', isDir: false, size: 24);
/// ```
class QuarkFileIcon extends StatelessWidget {
  /// Creates the icon for the entry called [name].
  const QuarkFileIcon({
    required this.name,
    required this.isDir,
    this.size = 20.0,
    this.color,
    super.key,
  });

  /// The file or folder name, including its extension. Case does not matter.
  final String name;

  /// Whether the entry is a directory, which wins over any extension.
  final bool isDir;

  /// The rendered glyph size in logical pixels.
  final double size;

  /// The glyph color. Defaults to the ambient [IconTheme] color.
  final Color? color;

  /// The icon for an entry called [name], without building a widget.
  ///
  /// Exposed for callers that need the glyph on its own — a list tile's
  /// leading slot, a menu entry, a drag feedback layer.
  static IconData iconFor(String name, {required bool isDir}) {
    if (isDir) return QuarkIcons.folder_outlined;
    final lower = name.toLowerCase();

    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.tiff') ||
        lower.endsWith('.tif') ||
        lower.endsWith('.raw') ||
        lower.endsWith('.cr2') ||
        lower.endsWith('.cr3') ||
        lower.endsWith('.nef') ||
        lower.endsWith('.arw') ||
        lower.endsWith('.dng') ||
        lower.endsWith('.orf') ||
        lower.endsWith('.rw2')) {
      return QuarkIcons.image_outlined;
    }

    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.wmv') ||
        lower.endsWith('.flv')) {
      return QuarkIcons.video_file_outlined;
    }

    if (lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.wma') ||
        lower.endsWith('.opus')) {
      return QuarkIcons.audio_file_outlined;
    }

    if (lower.endsWith('.pdf')) return QuarkIcons.picture_as_pdf_outlined;

    if (lower.endsWith('.zip') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.gz') ||
        lower.endsWith('.bz2') ||
        lower.endsWith('.xz') ||
        lower.endsWith('.7z') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.zst')) {
      return QuarkIcons.archive_outlined;
    }

    // Quark native formats
    if (lower.endsWith('.qdoc')) return QuarkIcons.edit_document;
    if (lower.endsWith('.qsheet')) return QuarkIcons.table_chart;
    if (lower.endsWith('.qslide')) return QuarkIcons.slideshow;

    if (lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.odt') ||
        lower.endsWith('.rtf')) {
      return QuarkIcons.description_outlined;
    }

    if (lower.endsWith('.xls') ||
        lower.endsWith('.xlsx') ||
        lower.endsWith('.ods') ||
        lower.endsWith('.csv')) {
      return QuarkIcons.table_chart_outlined;
    }

    if (lower.endsWith('.ppt') ||
        lower.endsWith('.pptx') ||
        lower.endsWith('.odp')) {
      return QuarkIcons.slideshow_outlined;
    }

    return QuarkIcons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Icon(
      iconFor(name, isDir: isDir),
      size: size,
      color: color,
    );
  }
}

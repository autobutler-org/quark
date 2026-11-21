import 'package:material_ui/material_ui.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';

/// A track's cover art from the Quark's thumbnail route, which reads a
/// track's embedded or folder cover when asked for the track's path.
///
/// Fills the [MusicCoverArt] it is built into. A track with no cover gets a
/// 404, and the surface behind it shows instead.
class MusicCover extends StatelessWidget {
  /// Shows the cover of the track at [path] on the drive [serial].
  const MusicCover({required this.path, this.serial = '', super.key});

  /// The track's path within its drive's files.
  final String path;

  /// The drive holding [path], empty for the internal drive.
  final String serial;

  /// A [MusicCoverArt] `coverBuilder` for the track at [path], or null for
  /// no path, which leaves the placeholder.
  static WidgetBuilder? builder(String path, String serial) =>
      path.isEmpty ? null : (_) => MusicCover(path: path, serial: serial);

  @override
  Widget build(BuildContext context) => Image(
    image: ThumbnailCacheManager.image(
      FilesService.constructThumbnailUrl(path, serial: serial),
    ),
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}

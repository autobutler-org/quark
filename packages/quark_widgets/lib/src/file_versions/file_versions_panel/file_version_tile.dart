import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../core/quark_loader.dart';
import '../../models/file_version_item.dart';
import '../../theme/quark_tokens.dart';
import '../format_version_time.dart';

/// One row of a `FileVersionsPanel`: when the version was saved, what it is
/// called, its size and who saved it, with a Preview and a Restore button.
///
/// Each button's tooltip, which is also its accessible name, names the
/// version — "Restore Draft 3, 7:09 AM" — so a screen reader can tell the
/// rows apart.
///
/// A null [onPreview] or [onRestore] dims its button. While [isBusy] the two
/// buttons give way to a loader, so a restore in flight reads as one.
///
/// Key prefixes: `file_version_tile_<id>` on the row,
/// `file_version_preview_<id>` and `file_version_restore_<id>` on its buttons.
class FileVersionTile extends StatelessWidget {
  /// Creates the row for [version].
  const FileVersionTile({
    required this.version,
    this.isBusy = false,
    this.onPreview,
    this.onRestore,
    super.key,
  });

  /// The version this row shows.
  final FileVersionItem version;

  /// Whether this version is being restored or fetched for a preview.
  final bool isBusy;

  /// Called when Preview is tapped. Null dims the button.
  final VoidCallback? onPreview;

  /// Called when Restore is tapped. Null dims the button.
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final detail = [
      if (version.label.isNotEmpty)
        version.label
      else
        version.isNamed ? 'Named' : 'Automatic',
      version.sizeLabel,
      if (version.author.isNotEmpty) version.author,
    ].join(' · ');
    final time = formatVersionTime(context, version.createdAt);
    final name = version.label.isNotEmpty
        ? '${version.label}, $time'
        : 'version from $time';

    return Padding(
      key: ValueKey('file_version_tile_${version.id}'),
      padding: EdgeInsets.symmetric(vertical: tokens.spacingXs),
      child: Row(
        children: [
          Icon(
            version.isNamed
                ? QuarkIcons.label_outline
                : QuarkIcons.access_time_outlined,
            color: tokens.secondaryForeground,
          ),
          SizedBox(width: tokens.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.secondaryForeground,
                  ),
                ),
              ],
            ),
          ),
          if (isBusy)
            Padding(
              padding: EdgeInsets.all(tokens.spacingSm),
              child: const QuarkLoader(size: 20),
            )
          else ...[
            IconButton(
              key: ValueKey('file_version_preview_${version.id}'),
              tooltip: 'Preview $name',
              icon: const Icon(QuarkIcons.visibility),
              onPressed: onPreview,
            ),
            IconButton(
              key: ValueKey('file_version_restore_${version.id}'),
              tooltip: 'Restore $name',
              icon: const Icon(QuarkIcons.restore),
              onPressed: onRestore,
            ),
          ],
        ],
      ),
    );
  }
}

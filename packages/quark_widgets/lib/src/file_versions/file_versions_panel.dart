import 'package:material_ui/material_ui.dart';

import '../core/quark_loader.dart';
import '../layout/refresh_icon_button.dart';
import '../models/file_version_item.dart';
import '../theme/quark_tokens.dart';
import 'file_versions_panel/file_version_tile.dart';

/// The saved versions of one file, newest first, each with a Preview and a
/// Restore action.
///
/// It never loads: the caller hands it [versions], [isLoading] and [error],
/// and decides what a tap does. With nothing to show yet, [isLoading] draws a
/// loader; once there are rows they stay on screen through a refresh. [error]
/// and [notice] are sentences the caller wrote, shown above the list. While
/// [busyId] names a version, that row shows a loader and every other row's
/// buttons are dimmed, so two restores cannot overlap. The panel does not
/// scroll; show it in a `QuarkSheet`, which does.
///
/// Key prefixes: `file_versions_panel` on the panel, `file_version_tile_<id>`
/// on each row, `file_version_preview_<id>` and `file_version_restore_<id>`
/// on a row's buttons. The refresh button keeps `RefreshIconButton`'s
/// `refresh_button`.
///
/// ```dart
/// FileVersionsPanel(
///   versions: controller.items,
///   isLoading: !controller.hasLoaded,
///   error: loadError,
///   busyId: controller.busyId,
///   onPreview: (id) => preview(id),
///   onRestore: (id) => confirmAndRestore(id),
///   onRefresh: manualRefresh,
///   isRefreshing: isRefreshing,
/// )
/// ```
class FileVersionsPanel extends StatelessWidget {
  /// Creates the panel over [versions].
  const FileVersionsPanel({
    required this.versions,
    this.isLoading = false,
    this.error,
    this.notice,
    this.busyId,
    this.onPreview,
    this.onRestore,
    this.onRefresh,
    this.isRefreshing = false,
    super.key,
  });

  /// The versions, rendered in the order they are given.
  final List<FileVersionItem> versions;

  /// Whether the first load is still out. Ignored once there are [versions].
  final bool isLoading;

  /// What went wrong, as a sentence the caller wrote. Null for nothing.
  final String? error;

  /// What just went right, such as a finished restore. Null for nothing.
  final String? notice;

  /// The [FileVersionItem.id] being restored or fetched, null when idle.
  final String? busyId;

  /// Called with a version's id when its Preview button is tapped. Null dims
  /// every Preview button.
  final ValueChanged<String>? onPreview;

  /// Called with a version's id when its Restore button is tapped. The panel
  /// does not ask first; the caller does. Null dims every Restore button.
  final ValueChanged<String>? onRestore;

  /// Called when the refresh button is tapped. Null leaves the button out.
  final VoidCallback? onRefresh;

  /// Whether a refresh is in flight, shown on the refresh button.
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final error = this.error;
    final notice = this.notice;
    final onPreview = this.onPreview;
    final onRestore = this.onRestore;
    final onRefresh = this.onRefresh;
    final idle = busyId == null;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: tokens.secondaryForeground,
    );

    return Column(
      key: const ValueKey('file_versions_panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Restoring a version saves the current one first.',
                style: muted,
              ),
            ),
            if (onRefresh != null)
              RefreshIconButton(
                onPressed: onRefresh,
                isRefreshing: isRefreshing,
              ),
          ],
        ),
        if (error != null)
          Padding(
            padding: EdgeInsets.only(top: tokens.spacingSm),
            child: Semantics(
              liveRegion: true,
              child: Text(error, style: TextStyle(color: tokens.error)),
            ),
          ),
        if (notice != null)
          Padding(
            padding: EdgeInsets.only(top: tokens.spacingSm),
            child: Semantics(
              liveRegion: true,
              child: Text(notice, style: TextStyle(color: tokens.success)),
            ),
          ),
        SizedBox(height: tokens.spacingSm),
        if (versions.isNotEmpty)
          for (final version in versions)
            FileVersionTile(
              version: version,
              isBusy: version.id == busyId,
              onPreview: idle && onPreview != null
                  ? () => onPreview(version.id)
                  : null,
              onRestore: idle && onRestore != null
                  ? () => onRestore(version.id)
                  : null,
            )
        else if (isLoading)
          Padding(
            padding: EdgeInsets.all(tokens.spacingLg),
            child: const Center(child: QuarkLoader()),
          )
        else if (error == null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spacingLg),
            child: Text(
              'No earlier versions yet. One is saved each time this file '
              'changes.',
              textAlign: TextAlign.center,
              style: muted,
            ),
          ),
      ],
    );
  }
}

import 'package:quark/models/file_node.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// One file in the "Recently uploaded" strip: the file's icon and name, with a
/// badge that jumps to the folder holding it.
///
/// The chip is at least 48dp tall, and the badge is a 48dp-wide strip down its
/// right side rather than a nested tap inside the chip, so each is a target a
/// finger can hit and a screen reader can name: the file, and "Go to folder"
/// (#2603, #2605).
///
/// Probe keys: `recent_file_<name>` and `recent_file_folder_<name>`.
class RecentFileChip extends StatelessWidget {
  const RecentFileChip({
    required this.file,
    required this.onTap,
    required this.onFolderTap,
    super.key,
  });

  final FileNode file;
  final VoidCallback onTap;
  final VoidCallback onFolderTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    return Material(
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(QuarkColors.radiusMd),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: ValueKey('recent_file_${file.name}'),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      QuarkFileIcon(
                        name: file.name,
                        isDir: file.isDir,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            if (file.deviceName.isNotEmpty)
                              Text(
                                file.deviceName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: tokens.mutedForeground,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Tooltip(
                message: 'Go to folder',
                child: InkWell(
                  key: ValueKey('recent_file_folder_${file.name}'),
                  onTap: onFolderTap,
                  child: SizedBox(
                    width: kMinInteractiveDimension,
                    child: Icon(
                      QuarkIcons.folder_open_rounded,
                      size: 14,
                      color: tokens.secondaryForeground,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

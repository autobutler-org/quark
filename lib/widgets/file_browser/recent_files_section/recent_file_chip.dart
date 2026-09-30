import 'package:quark/models/file_node.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// One file in the "Recently uploaded" strip: the file's icon and name, with a
/// badge that jumps to the folder holding it.
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colorScheme.outline),
          borderRadius: BorderRadius.circular(QuarkColors.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
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
                            color: colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                    ],
                  ),
                ),
                // Folder navigate badge, a full 48 pixel target (#2605).
                IconButton(
                  tooltip: 'Go to folder',
                  onPressed: onFolderTap,
                  icon: const Icon(QuarkIcons.folder_open_rounded),
                  iconSize: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

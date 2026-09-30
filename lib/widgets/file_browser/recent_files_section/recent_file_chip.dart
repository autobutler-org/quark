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
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
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
                            color: QuarkTokens.of(context).mutedForeground,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Folder navigate badge
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Tooltip(
                    message: 'Go to folder',
                    child: InkWell(
                      onTap: onFolderTap,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          QuarkIcons.folder_open_rounded,
                          size: 14,
                          color: QuarkTokens.of(context).secondaryForeground,
                        ),
                      ),
                    ),
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

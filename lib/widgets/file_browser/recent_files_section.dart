import 'package:quark/models/file_node.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/widgets/file_browser/recent_files_section/recent_file_chip.dart';
import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// A horizontally-scrolling strip showing recently uploaded files.
/// Displayed at the root of the file browser (not in search mode).
///
/// Tapping a file chip calls [onOpenFile], the same handler the main file list
/// uses, so every file kind opens the same way in both places.
/// Tapping the folder badge triggers [onNavigateToFolder] with the parent directory path.
///
/// Changing [refreshToken] fetches the list again in place: the last list
/// stays on screen until the new one arrives, so a refresh never collapses the
/// strip (#2446).
class RecentFilesSection extends StatefulWidget {
  const RecentFilesSection({
    required this.onOpenFile,
    required this.onNavigateToFolder,
    this.refreshToken = 0,
    this.getRecentFiles = FilesService.getRecentFiles,
    super.key,
  });

  final void Function(FileNode) onOpenFile;
  final void Function(String path) onNavigateToFolder;

  /// Bump to refetch the list without remounting the strip.
  final int refreshToken;

  /// Fetches the recent files; injectable for tests.
  final Future<List<FileNode>> Function({int limit, List<String>? serials})
  getRecentFiles;

  @override
  State<RecentFilesSection> createState() => _RecentFilesSectionState();
}

class _RecentFilesSectionState extends State<RecentFilesSection> {
  late Future<List<FileNode>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.getRecentFiles(limit: 20);
  }

  @override
  void didUpdateWidget(RecentFilesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) {
      // FutureBuilder keeps the previous snapshot's data while the new future
      // is pending, so the old chips stay up until the refetch lands.
      _future = widget.getRecentFiles(limit: 20);
    }
  }

  String _parentPath(FileNode node) {
    final path = node.apiPath;
    final slash = path.lastIndexOf('/');
    if (slash <= 0) return '';
    return path.substring(0, slash);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FileNode>>(
      future: _future,
      builder: (context, snapshot) {
        // Don't show section at all while loading or on error or if empty.
        if (!snapshot.hasData || snapshot.hasError) {
          return const SizedBox.shrink();
        }
        final files = snapshot.data!.where((f) => !f.isDir).toList();
        if (files.isEmpty) return const SizedBox.shrink();

        final colorScheme = Theme.of(context).colorScheme;
        return Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colorScheme.outline)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    QuarkIcons.schedule_rounded,
                    size: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Recently uploaded',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return RecentFileChip(
                      file: file,
                      onTap: () => widget.onOpenFile(file),
                      onFolderTap: () =>
                          widget.onNavigateToFolder(_parentPath(file)),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// One doc or sheet in the Docs and Sheets lists, whether it matched by name
/// or by content, so the same file looks the same either way (#2272).
///
/// The file's own extension picks its icon, so a sheet on the Docs page still
/// looks like a sheet.
class DocSheetTile extends StatelessWidget {
  /// Path relative to the device's files root, e.g. `reports/q1.qdoc`.
  final String relPath;

  /// Shown before the folder only when [showDevice] is set.
  final String deviceName;

  /// Whether the rows being shown span more than one device, so the device
  /// name tells same-named files apart instead of repeating on every row.
  final bool showDevice;

  /// Matched text from a content search, shown under the location.
  final String? snippet;
  final VoidCallback onTap;

  /// Offered from the row's menu, keyed `doc_sheet_menu_<relPath>` and
  /// `doc_sheet_rename_<relPath>`. With none the row has no menu.
  final VoidCallback? onRename;

  const DocSheetTile({
    required this.relPath,
    required this.deviceName,
    required this.showDevice,
    required this.onTap,
    this.snippet,
    this.onRename,
    super.key,
  });

  /// Whether [relPath] names a spreadsheet rather than a document.
  static bool isSheet(String relPath) =>
      relPath.toLowerCase().endsWith('.qsheet');

  /// Whether [relPath] names a document.
  static bool isDoc(String relPath) => relPath.toLowerCase().endsWith('.qdoc');

  /// Identifies a file across a filename listing and a content search, which
  /// spell the same path with and without a leading slash.
  static String fileKey(String deviceSerial, String relPath) =>
      '$deviceSerial:${relPath.replaceAll(RegExp(r'^/+'), '')}';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sheet = isSheet(relPath);
    final accent = sheet ? Colors.green.shade600 : colorScheme.primary;

    final slash = relPath.lastIndexOf('/');
    final filename = relPath.substring(slash + 1);
    final folder = slash < 0 ? '' : relPath.substring(0, slash);
    final location = [
      if (showDevice && deviceName.isNotEmpty) deviceName,
      if (folder.isNotEmpty) folder,
    ].join(' · ');
    final snippet = this.snippet;
    final subtitleStyle = TextStyle(
      fontSize: 12,
      color: colorScheme.onSurface.withValues(alpha: 0.55),
    );

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          sheet
              ? QuarkIcons.table_chart_outlined
              : QuarkIcons.description_outlined,
          size: 18,
          color: accent,
        ),
      ),
      title: Text(
        filename.replaceAll(
          RegExp(r'\.(qdoc|qsheet)$', caseSensitive: false),
          '',
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: location.isEmpty && snippet == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (location.isNotEmpty)
                  Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
                if (snippet != null)
                  Text(
                    snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
              ],
            ),
      trailing: onRename == null
          ? null
          : PopupMenuButton<VoidCallback>(
              key: ValueKey('doc_sheet_menu_$relPath'),
              tooltip: 'More',
              icon: const Icon(Icons.more_vert),
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: ValueKey('doc_sheet_rename_$relPath'),
                  value: onRename,
                  child: const Text('Rename'),
                ),
              ],
            ),
      onTap: onTap,
    );
  }
}
